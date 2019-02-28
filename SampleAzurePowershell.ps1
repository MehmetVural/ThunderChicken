# Azure Account

#Connect-AzureRmAccount

#powershell -executionpolicy bypass

# region variables
$QuickSartDirectory = "U:\github\ThunderChicken" # set samples directory

Write-Host "Setting Location for Azure Templates Master"
Set-Location -Path $QuickSartDirectory

$ArtifactStagingDirectory =  "master-template" #Read-Host 'What is template directory?'
$ResourceGroupName =  Read-Host 'What is Resource Group Name?'

if ($ArtifactStagingDirectory ){    
    .\Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation 'eastus' `
                                    -ResourceGroupName $ResourceGroupName `
                                    -ArtifactStagingDirectory $ArtifactStagingDirectory  `
                                    -UploadArtifacts #-ValidateOnly  `
}