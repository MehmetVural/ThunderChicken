# This Script publishes DSC configurations to Azure Automation DSC, complies MOF Files, Registeres each Azure VMs with Azure Automation pull server and registers MOF Files to each Azure VM defined in Config Data
# Run this script from you workstation directly
# AzureRM.Profile, AzureRM.Automation  (Required Modules for this script)  

#Requires -Version 3.0
#Requires -Module AzureRM.Resources
#Requires -Module Azure.Storage
#Requires -Module @{ModuleName="AzureRm.Profile";ModuleVersion="3.0"}

# Azure Account 
# Connect-AzureRmAccount

#DSC Configuration files
$DSCconfigFile = "SQLSetup.ps1"
$ConfigurationName = "SQLSetup"
$DSCconfigDataFile = "SQLSetupData.psd1"
$DSCMofFolder = 'SQLSetup'
#DSC Automation config
$ConfigurationMode = "ApplyandAutoCorrect"  #ApplyOnly, ApplyAndMonitor, ApplyAndAutoCorrect
$AutomationAccountName = "DSCAutomationAccount"

Write-Host "Registering Configuration" -ForegroundColor Yellow

#Push-Location (Split-Path -Path $MyInvocation.MyCommand.Definition -Parent)

$DSCconfigFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCconfigFile))
$DSCconfigDataFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCconfigDataFile))
$DSCMofFolder = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCMofFolder))

$ConfigData = Import-PowerShellDataFile $DSCconfigDataFile

# Check AzureAutomation Account, if Null, create one
$vm = Get-AzureRMVM | Where-Object Name -like "VD201" | Select-Object ResourceGroupName, Name, Location
if ($vm) { $ResourceGroupName = $vm.ResourceGroupName }
$AutomationAccount = Get-AzureRmAutomationAccount | Where-Object AutomationAccountName -eq $AutomationAccountName
if ($vm -and !$AutomationAccount) { $AutomationAccount = New-AzureRmAutomationAccount -Name $AutomationAccountName -Location "East US 2" -ResourceGroupName $ResourceGroupName }
$AutomationAccountName = $AutomationAccount.AutomationAccountName 

if ($AutomationAccount -and $vm) {
    # Import Configuraiton into Azure DSC Automation
    Write-Host "Importing Configuration to Azure DSC" -ForegroundColor Yellow
    #$DSCImport = Import-AzureRmAutomationDscConfiguration -SourcePath $DSCconfigFile -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Published -Force

    # Complies MOF Files for each nodes defined in DSCconfigDataFile
    Write-Host "Compling MOF Files for each node in config data" -ForegroundColor Yellow
    # Create DSC configuration archive
    ##$DSCComp = Start-AzureRmAutomationDscCompilationJob -AutomationAccountName $AutomationAccountName -ConfigurationName $ConfigurationName -ConfigurationData $ConfigData -ResourceGroupName  $ResourceGroupName

    # Import Pre-build moff files if applicable
    if (Test-Path $DSCMofFolder) {
        $DSCSourceFilePaths = @(Get-ChildItem $DSCMofFolder -File -Filter '*.mof' | ForEach-Object -Process {$_.FullName})
        foreach ($DSCSourceFilePath in $DSCSourceFilePaths) {
            #$DSCArchiveFilePath = $DSCSourceFilePath.Substring(0, $DSCSourceFilePath.Length - 4) + '.moff'
            Write-Host $DSCSourceFilePath
            $DSCMof = Import-AzureRmAutomationDscNodeConfiguration -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -ConfigurationName $ConfigurationName -Path $DSCSourceFilePath -Force 
        }
    }

    Write-Host "Searching each node if it is registered with Azure DSC or not" 
    $ConfigData.AllNodes | Where-Object {$_.NodeName -ne "*"} | ForEach-Object {
    
        $NodeName = $_.NodeName
        # check if node is already registered or not with Azure DSC Automation pull server
        $getDSCNode = Get-AzureRmAutomationDscNode -ResourceGroupName  $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $NodeName
    
        if (!$getDSCNode ) {
            Write-Host "$NodeName - None Registered Node - Registering" -ForegroundColor Yellow
            $nodeConfigurationName = $ConfigurationName + '.' + $NodeName

            # Register each VM to Azure DSC Pull Server for MOF pull
            Register-AzureRmAutomationDscNode -ResourceGroupName $ResourceGroupName -AzureVMResourceGroup $ResourceGroupName  -AutomationAccountName $AutomationAccountName -ConfigurationMode $ConfigurationMode -NodeConfigurationName $nodeConfigurationName -AzureVMName $NodeName -AzureVMLocation $vm.Location -Verbose
        }
    }

    # List all registered Nodes.
    #Get-AzureRmAutomationDscNode -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
}

