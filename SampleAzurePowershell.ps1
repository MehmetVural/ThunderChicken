# Azure Account

$Global:ServicePath = $PSScriptRoot

# Imports Common CI Utilities
  Write-Host "Importing CI Common functions"
  if((Get-Module -Name 'CI.Common')){ Remove-Module -Name 'CI.Common' }
  Import-Module -Name (Join-Path -Path (Join-Path -Path (Split-Path -Path $Global:ServicePath  ) -ChildPath "CI.Common") -ChildPath 'CI.Common.psd1') -DisableNameChecking 
#


Write-Host "Test if it is connected to Microsoft Azure" -ForegroundColor Yellow
# login to Azure Account #Connect-AzureRmAccount
Login-Azure

#powershell -executionpolicy bypass

# region variables
$QuickSartDirectory = $PSScriptRoot # set samples directory

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