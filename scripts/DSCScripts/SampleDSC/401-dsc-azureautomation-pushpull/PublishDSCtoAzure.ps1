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
$DSCconfigFile = "DSCConfig.ps1"
$ConfigurationName = "DSCConfig"
$DSCconfigDataFile = "DSCConfigData.psd1"

#DSC Automation config
$ConfigurationMode = "ApplyandAutoCorrect"  #ApplyOnly, ApplyAndMonitor, ApplyAndAutoCorrect
$AutomationAccountName = "DSCAutomationAccount"

Write-Host "Registering Configuration" -ForegroundColor Yellow

$DSCconfigFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCconfigFile))
$DSCconfigDataFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCconfigDataFile))

$ConfigData = Import-PowerShellDataFile $DSCconfigDataFile

# Check AzureAutomation Account, if Null, create one
$vm = Get-AzureRMVM | Where-Object Name -like "master-dc1vm" | Select-Object ResourceGroupName, Name, Location
if ($vm) { $ResourceGroupName = $vm.ResourceGroupName }
$AutomationAccount = Get-AzureRmAutomationAccount | Where-Object AutomationAccountName -eq $AutomationAccountName
if ($vm -and !$AutomationAccount) { $AutomationAccount = New-AzureRmAutomationAccount -Name $AutomationAccountName -Location "East US 2" -ResourceGroupName $ResourceGroupName }
$AutomationAccountName = $AutomationAccount.AutomationAccountName 

if ($AutomationAccount -and $vm) {
    # Import Configuraiton into Azure DSC Automation
    Write-Host "Importing Configuration to Azure DSC" -ForegroundColor Yellow
    $DSCImport = Import-AzureRmAutomationDscConfiguration -SourcePath $DSCconfigFile -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Published -Force

    # Complies MOF Files for each nodes defined in DSCconfigDataFile
    Write-Host "Compling MOF Files for each node in config data" -ForegroundColor Yellow
    $DSCComp = Start-AzureRmAutomationDscCompilationJob -AutomationAccountName $AutomationAccountName -ConfigurationName $ConfigurationName -ConfigurationData $ConfigData -ResourceGroupName  $ResourceGroupName
    
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
}