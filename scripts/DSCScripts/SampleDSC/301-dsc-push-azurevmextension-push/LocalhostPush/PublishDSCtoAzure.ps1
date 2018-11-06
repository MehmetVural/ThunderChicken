# This Script publishes DSC configurations to all Azure VMs defined in config data 
# Run this script from you workstation directly
# AzureRM.Profile, AzureRM.Automation,  AzureRM.Compute  (Required Modules for this script)  

# Uncomment this line below, if you are not already opened Azure Session. This will let you login to desired Azure subscription
# Connect-AzureRmAccount

$DSCconfigFile = "DSCConfig.ps1"
$ConfigurationName = "DSCConfig"
#$DSCconfigDataFile =  "DSCConfigData.psd1"
$ResourceGroupName = "ThunderChicken"

Write-Host "Registering Configuration"

$DSCconfigFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCconfigFile))
#$DSCconfigDataFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCconfigDataFile))

#$ConfigData = Import-PowerShellDataFile $DSCconfigDataFile

$storageName = 'masterdjyr55yornmvo' # DSC will be storad here before pushed into Azure VM

# Publish the configuration script to user storage defined above
$ArchiveZipFile = Publish-AzureRmVMDscConfiguration -ConfigurationPath $DSCconfigFile -ResourceGroupName $ResourceGroupName -StorageAccountName $storageName -force

Set-AzureRmVMDscExtension -Version '2.77' -ResourceGroupName $ResourceGroupName -VMName 'sp-ks-vm1'  -ArchiveBlobName "DSCConfig.ps1.zip" -ArchiveStorageAccountName $storageName -ConfigurationName $ConfigurationName -ArchiveContainerName "windows-powershell-dsc" -Location "East US"    

#$ConfigData.AllNodes | where {$_.NodeName -ne "*"} | ForEach-Object{

#    $NodeName = $_.NodeName    
#    #$AzureVm = Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Status | Where-Object { $_.Name -eq $NodeName} | ForEach-Object -Process {$_} 
#    #$AzureVm.Extensions       
#    Set-AzureRmVMDscExtension -Version '2.77' -ResourceGroupName $ResourceGroupName -VMName $NodeName -ArchiveBlobName "DSCConfig.ps1.zip" -ArchiveStorageAccountName $storageName -ConfigurationName $ConfigurationName -ArchiveContainerName "windows-powershell-dsc" -ConfigurationData $DSCconfigDataFile -Location "East US"    
#}