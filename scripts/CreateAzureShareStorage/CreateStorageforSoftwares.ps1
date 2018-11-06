
# This script willl create software share resources in Azure.

#Requires -Version 3.0
#Requires -Module AzureRM.Resources
#Requires -Module AzureRM.Storage
#Requires -Module @{ModuleName="AzureRm.Profile";ModuleVersion="3.0"}

#Connect-AzureRmAccount

# change
$Location     =   Read-Host -Prompt "Input share location for softwares" # local location to upload files
$sourceFolder =   Read-Host -Prompt "Input folder to upload"  # Folder to upload based on services

Write-Host $Location -ForegroundColor Yellow
Write-Host $sourceFolder -ForegroundColor Yellow

# Do not change, these are constant for the project
$ResourceGroupLocation = "eastus"
$StorageResourceGroupName = "ThunderChickenShare"
$StorageContainerName = "share"
$UploadArtifacts = $true

try {
    [Microsoft.Azure.Common.Authentication.AzureSession]::ClientFactory.AddUserAgent("AzureQuickStarts-$UI$($host.name)".replace(" ","_"), "1.0")
} catch { }


$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

# Create a storage account name if none was provided

$StorageAccountName = 'share' + ((Get-AzureRmContext).Subscription.Id).Replace('-', '').substring(0, 19)


# Convert relative paths to absolute paths if needed
    
$StorageAccount = (Get-AzureRmStorageAccount | Where-Object{$_.StorageAccountName -eq $StorageAccountName})

# Create the storage account if it doesn't already exist
if ($StorageAccount -eq $null) {

    New-AzureRmResourceGroup -Location "$ResourceGroupLocation" -Name $StorageResourceGroupName -Force
    $StorageAccount = New-AzureRmStorageAccount -StorageAccountName $StorageAccountName -Type 'Standard_LRS' -ResourceGroupName $StorageResourceGroupName -Location "$ResourceGroupLocation"
   
}

$StorageFileShare =  (Get-AzureStorageShare -Context $StorageAccount.Context | Where-Object{$_.Name -eq $StorageContainerName})

if ($StorageFileShare -eq $null) {
    $StorageFileShare = New-AzureStorageShare -Name $StorageContainerName -Context $StorageAccount.Context 
    #Set-AzureStorageShareQuota -ShareName $StorageContainerName -Quota  10240
}

$softwareKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $StorageAccount.ResourceGroupName `
                                                 -Name $StorageAccountName
$Location  = $Location + '\' + $sourceFolder    

if ($UploadArtifacts -and (Test-Path $Location))
{
    
    Write-Host "Uploading softwares..." -ForegroundColor Yellow
    # get all the folders in the source directory
    # create top folder for service
    
    New-AzureStorageDirectory -Share $StorageFileShare -Path $sourceFolder -ErrorAction SilentlyContinue

    $Folders = Get-ChildItem -Path $Location  -Directory -Recurse
    foreach($Folder in $Folders)
    {
        $f = ($Folder.FullName).Substring(($Location.Length+1))
        $Path = $sourceFolder + '\' + $f
        #$Path = $f
        $Path
        New-AzureStorageDirectory -Share $StorageFileShare -Path $Path -ErrorAction SilentlyContinue
    }

    $ArtifactFilePaths = Get-ChildItem $Location -Recurse -File | ForEach-Object -Process {$_.FullName}
    foreach ($SourcePath in $ArtifactFilePaths) {
        #Write-host $SourcePath
        $DestPath = $sourceFolder + '\' + $SourcePath.Substring($Location.length + 1)   
        $SourcePath 
        Set-AzureStorageFileContent -Share $StorageFileShare -Source $SourcePath -Path $DestPath -Force  -ErrorAction SilentlyContinue        
    }
}
