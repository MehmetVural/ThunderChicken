# This Script publishes DSC configurations to Azure Automation DSC, complies MOF Files, Registeres each Azure VMs with Azure Automation pull server and registers MOF Files to each Azure VM defined in Config Data
# Run this script from you workstation directly
# AzureRM.Profile, AzureRM.Automation  (Required Modules for this script)  

#Requires -Version 3.0
#Requires -Module AzureRM.Resources
#Requires -Module Azure.Storage
#Requires -Module @{ModuleName="AzureRm.Profile";ModuleVersion="3.0"}


# Uncomment this line below, if you are not already opened Azure Session. This will let you login to desired Azure subscription
# Connect-AzureRmAccount

$DSCconfigFile = "DSCConfig.ps1"
$ConfigurationName = "DSCConfig"
$DSCconfigDataFile =  "DSCConfigData.psd1"
$ResourceGroupName = "ThunderChicken"

$ConfigurationMode = "ApplyandAutoCorrect"  #ApplyOnly, ApplyAndMonitor, ApplyAndAutoCorrect

$AutomationAccountName = "DSCAutomationAccount"

Write-Host "Registering Configuration"

$DSCconfigFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCconfigFile))
$DSCconfigDataFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCconfigDataFile))

$ConfigData = Import-PowerShellDataFile $DSCconfigDataFile

#$AutomationAccount = Get-AzureRmAutomationAccount -AutomationAccountName $AutomationAccountName
#$AutomationAccount

Import-AzureRmAutomationDscConfiguration -SourcePath $DSCconfigFile -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Published -Force
#Start-AzureRmAutomationDscCompilationJob -ConfigurationName $ConfigurationName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName

$DSCComp = Start-AzureRmAutomationDscCompilationJob -AutomationAccountName $AutomationAccountName -ConfigurationName $ConfigurationName -ConfigurationData $ConfigData -ResourceGroupName  $ResourceGroupName

$ConfigData.AllNodes | where {$_.NodeName -ne "*"} | ForEach-Object{
    
    $NodeName = $_.NodeName
    $getDSCNode =   Get-AzureRmAutomationDscNode -ResourceGroupName  $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $NodeName
    
    if(!$getDSCNode )
    {
        Write-Host "$NodeName - Not Registered"
        $nodeConfigurationName = $ConfigurationName +'.' + $NodeName
        #$nodeConfigurationName
        Register-AzureRmAutomationDscNode -ResourceGroupName $ResourceGroupName -AzureVMResourceGroup $ResourceGroupName  -AutomationAccountName $AutomationAccountName -ConfigurationMode $ConfigurationMode -NodeConfigurationName $nodeConfigurationName -AzureVMName $NodeName -AzureVMLocation "East US" -Verbose
    }
}