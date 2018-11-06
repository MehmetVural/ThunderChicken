#Install Modules  Install-Module Azure;  Install-Module -Name AzureRM.Resources -RequiredVersion 6.4.2; Install-Module AzureRM

#Import Modules
#Import-Module Azure
#Import-Module AzureRM
#Import-Module AzureRM.Resources

#Add-AzureAccount Fall#1205
#Connect-AzureRmAccount

#Select-AzureRmSubscription -SubscriptionName <yourSubscriptionName>  #select subscription

# region variables
$QuickSartDirectory = "C:\github\ThunderChicken" # set samples directory
#$ArtifactStagingDirectory =  '201-nsg-dmz-in-vnet' #"01-mehmet-template-blank" #100-blank-template #101-1vm-2nics-2subnets-1vnet #01-mehmet-template #sharepoint-server-farm-ha #sharepoint-three-vm #01-mehmet-sharepoint-server-farm-ha

Write-Host "Setting Location for Azure Templates Master"
Set-Location -Path $QuickSartDirectory

$ArtifactStagingDirectory =  "master-template" #"master-template" #"201-vm-custom-script-windows" #"01-mehmet-sharepoint-server-farm-ha" #"01-mehmet-sharepoint-three-vm" #Read-Host 'What is template directory?'

if ($ArtifactStagingDirectory ){
    #.\Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation 'eastus' -ArtifactStagingDirectory $ArtifactStagingDirectory#
    #.\Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation 'eastus' -ArtifactStagingDirectory $ArtifactStagingDirectory -UploadArtifacts -DSCSourceFolder 'dscv2' 
    #-AdminCredential (Get-Credential -Messagae "Enter admin credential")
    .\Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation 'eastus' `
                                    -ResourceGroupName 'ThunderChicken2' `
                                    -ArtifactStagingDirectory $ArtifactStagingDirectory  `
                                    -UploadArtifacts #-ValidateOnly  ` 
}

