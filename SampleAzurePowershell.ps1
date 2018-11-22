# Azure Account
#Connect-AzureRmAccount

# region variables
$QuickSartDirectory = "C:\github\ThunderChicken" # set samples directory

Write-Host "Setting Location for Azure Templates Master"
Set-Location -Path $QuickSartDirectory

$ArtifactStagingDirectory =  Read-Host 'What is template directory?'
$ResourceGroupName =  Read-Host 'What is Resource Group Name?'

if ($ArtifactStagingDirectory ){    
    .\Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation 'eastus' `
                                    -ResourceGroupName $ResourceGroupName `
                                    -ArtifactStagingDirectory $ArtifactStagingDirectory  `
                                    -UploadArtifacts #-ValidateOnly  `
}