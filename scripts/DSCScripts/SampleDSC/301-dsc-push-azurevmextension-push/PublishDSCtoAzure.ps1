# This Script publishes DSC to AzureVM thourhg AzureVM DSC Estension. 
# Run this script from you workstation directly
# AzureRM.Profile, AzureRM.Compute  (Required Modules for this script)  

# Azure Account 
Connect-AzureRmAccount

$DSCconfigFile = "DSCConfig.ps1"
$ConfigurationName = "DSCConfig"
$ResourceGroupName = "ThunderChicken"

Write-Host "Registering Configuration"

$DSCconfigFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCconfigFile))

$storageName = 'masterdjyr55yornmvo' # DSC will be storad here before pushed into Azure VM

# Publish the configuration script to user storage defined above
$ArchiveZipFile = Publish-AzureRmVMDscConfiguration -ConfigurationPath $DSCconfigFile -ResourceGroupName $ResourceGroupName -StorageAccountName $storageName -force

Set-AzureRmVMDscExtension -Version '2.77' -ResourceGroupName $ResourceGroupName -VMName 'sp-ks-vm1'  -ArchiveBlobName "DSCConfig.ps1.zip" -ArchiveStorageAccountName $storageName -ConfigurationName $ConfigurationName -ArchiveContainerName "windows-powershell-dsc" -Location "East US"    

