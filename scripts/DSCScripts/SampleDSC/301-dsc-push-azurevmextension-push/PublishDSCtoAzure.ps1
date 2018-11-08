# This Script publishes DSC to AzureVM thourhg AzureVM DSC Estension. 
# Run this script from you workstation directly
# AzureRM.Profile, AzureRM.Compute  (Required Modules for this script)  

# Azure Account 
#Connect-AzureRmAccount

$DSCconfigFile = "DSCConfig.ps1"
$ConfigurationName = "DSCConfig"
$VMName = 'sp-ks-vm1'

Write-Host "Uploading and Registering Configuration" -ForegroundColor Yellow

$DSCconfigFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCconfigFile))

# Check Vm, storage Accounts
$vm = Get-AzureRMVM | Where-Object Name -like "master-dc1vm" | Select-Object ResourceGroupName, Name, Location
if ($vm) { $ResourceGroupName = $vm.ResourceGroupName }
$vmforDSC = Get-AzureRMVM | Where-Object Name -like $VMName | Select-Object ResourceGroupName, Name, Location
$storageAccount = Get-AzureRmStorageAccount | Where-Object ResourceGroupName -eq $ResourceGroupName | Select-Object StorageAccountName
if($storageAccount){$storageName = $storageAccount.StorageAccountName}

# if vm and stroage account exist, then push zip configuration and push DSC extension to VM
if($vmforDSC -and $storageAccount) {
    # Publish the configuration script to user storage defined above
    $ArchiveZipFile = Publish-AzureRmVMDscConfiguration -ConfigurationPath $DSCconfigFile -ResourceGroupName $ResourceGroupName -StorageAccountName $storageName -force
    $filename = $ArchiveZipFile.Substring($ArchiveZipFile.LastIndexOf("/") + 1)    
    Set-AzureRmVMDscExtension -Version '2.77' -ResourceGroupName $ResourceGroupName -VMName $VMName  -ArchiveBlobName $filename -ArchiveStorageAccountName $storageName -ConfigurationName $ConfigurationName -ArchiveContainerName "windows-powershell-dsc" -Location $vmforDSC.Location    
}
