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
$DSCconfigFile = "ConfigureSQL.ps1"
$ConfigurationName = "ConfigureSQL"
$DSCconfigDataFile = "ConfigureSQLData.psd1"
$DSCMofFolder = ''
#DSC Automation config
$ConfigurationMode = "ApplyandAutoCorrect"  #ApplyOnly, ApplyAndMonitor, ApplyAndAutoCorrect
$RebootNodeIfNeeded = $true
$AutomationAccountName = "DSCAccount"
$AzureVMLocation = "eastus" 
Write-Host "Starting..." -ForegroundColor Yellow


#Push-Location (Split-Path -Path $MyInvocation.MyCommand.Definition -Parent)

$DSCconfigFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCconfigFile))
$DSCconfigDataFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCconfigDataFile))
$DSCMofFolder = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCMofFolder))

$ConfigData = Import-PowerShellDataFile $DSCconfigDataFile
Write-Host "Searching Resource groups." -ForegroundColor Yellow
# Check AzureAutomation Account, if Null, create one 
$vm = Get-AzureRMVM | Where-Object Name -like "VD201" | Select-Object ResourceGroupName, Name, Location
$ResourceGroupName = $null
function selectOptions
{
    param( [string[]]$ResourceGroupName)    
    $option = 1;
    Write-Host "Available resource groups to deploy:" 
    $ResourceGroupName | ForEach-Object -Process {
        Write-Host "$option) $_" -ForegroundColor Yellow
        $option += 1 ;
    }
}

if ($vm) { $ResourceGroupName = $vm.ResourceGroupName }

if($ResourceGroupName.Length -gt 1 -and $vm -is [system.array]) 
{   
    do {
        try {
            selectOptions($ResourceGroupName)
            $numOk = $true
            [int]$selected = Read-host "Select available Resource group between 1 to $($ResourceGroupName.Length)" 
            } # end try
        catch {$numOK = $false}
    } # end do 
    until (($selected -ge 1 -and $selected -le $ResourceGroupName.Length) -and $numOK)

    #$selected = Read-Host "Select ResourceGroup to deploy"
    $ResourceGroupName = $ResourceGroupName[$selected-1]    
    $AzureVMLocation = $vm[$selected-1].location
}
else
{  
  $ResourceGroupName = $ResourceGroupName   
  $AzureVMLocation = $vm.location
}

if($null -eq $ResourceGroupName)
{
    Write-Host "Resource Group not found. Exiting" -ForegroundColor Red
    Exit
}

$AutomationAccountName += $ResourceGroupName

Write-Host "Configurations will be deployed in $ResourceGroupName" -ForegroundColor Yellow

Write-Host "Creating Automation Account" -ForegroundColor Yellow

$AutomationAccount = Get-AzureRmAutomationAccount -ResourceGroupName $ResourceGroupName | Where-Object AutomationAccountName -eq $AutomationAccountName
#$AutomationAccount = Get-AzureRmAutomationAccount -ResourceGroupName $ResourceGroupName | Where-Object AutomationAccountName -eq $AutomationAccountName

if ($vm -and !$AutomationAccount) { $AutomationAccount = New-AzureRmAutomationAccount -Name $AutomationAccountName -Location "East US 2" -ResourceGroupName $ResourceGroupName }
$AutomationAccountName = $AutomationAccount.AutomationAccountName 

if ($AutomationAccount -and $vm) {
    # Import Configuraiton into Azure DSC Automation
    Write-Host "Importing Configuration to Azure DSC" -ForegroundColor Yellow
    $DSCImport = Import-AzureRmAutomationDscConfiguration -SourcePath $DSCconfigFile -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Published -Force

    # Complies MOF Files for each nodes defined in DSCconfigDataFile
    Write-Host "Compling MOF Files for each node in config data" -ForegroundColor Yellow
    # Create DSC configuration archive
    $DSCComp = Start-AzureRmAutomationDscCompilationJob -AutomationAccountName $AutomationAccountName -ConfigurationName $ConfigurationName -ConfigurationData $ConfigData -ResourceGroupName  $ResourceGroupName

    # Import Pre-build moff files if applicable
    # if (Test-Path $DSCMofFolder) {
    #     $DSCSourceFilePaths = @(Get-ChildItem $DSCMofFolder -File -Filter '*.mof' | ForEach-Object -Process {$_.FullName})
    #     foreach ($DSCSourceFilePath in $DSCSourceFilePaths) {
    #         #$DSCArchiveFilePath = $DSCSourceFilePath.Substring(0, $DSCSourceFilePath.Length - 4) + '.moff'
    #         Write-Host $DSCSourceFilePath
    #         $DSCMof = Import-AzureRmAutomationDscNodeConfiguration -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -ConfigurationName $ConfigurationName -Path $DSCSourceFilePath -Force 
    #     }
    # }

    Write-Host "Searching each node if it is registered with Azure DSC or not" 
    $ConfigData.AllNodes | Where-Object {$_.NodeName -ne "*"} | ForEach-Object {
    
        $NodeName = $_.NodeName
        # check if node is already registered or not with Azure DSC Automation pull server
        $getDSCNode = Get-AzureRmAutomationDscNode -ResourceGroupName  $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $NodeName
    
        if (!$getDSCNode ) {
            Write-Host "$NodeName - None Registered Node - Registering" -ForegroundColor Yellow
            $nodeConfigurationName = $ConfigurationName + '.' + $NodeName

            # Register each VM to Azure DSC Pull Server for MOF pull
            Register-AzureRmAutomationDscNode -ResourceGroupName $ResourceGroupName -AzureVMResourceGroup $ResourceGroupName  -AutomationAccountName $AutomationAccountName -ConfigurationMode $ConfigurationMode -RebootNodeIfNeeded $RebootNodeIfNeeded -NodeConfigurationName $nodeConfigurationName -AzureVMName $NodeName -AzureVMLocation $AzureVMLocation -Verbose 
        }
    }

    # List all registered Nodes.
    #Get-AzureRmAutomationDscNode -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
}

