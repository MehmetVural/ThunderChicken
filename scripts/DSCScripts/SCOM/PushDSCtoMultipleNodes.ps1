# This Script complies MOF files for each computer and pushes configuration to all computers and start DSC configuration
# computers are defined in .\DSCConfigData.psd1 file 
# RDP to VM, copy these files into a folder, run PushDSCtoMultipleNodes.ps1 file 

Push-Location (Split-Path -Path $MyInvocation.MyCommand.Definition -Parent)

. .\SCOMSetup.ps1 

#copy dsc resources modules from share file to each nodes Program Files\WindowsPowerShell\Modules folder
$config = Import-PowerShellDataFile .\SCOMSetupData.psd1 
if( $null -ne $config.NonNodeData.ModulesPath){
    $config.AllNodes.NodeName | ForEach-Object {
        $NodeName = $_ 
        Copy-Item -Path $config.NonNodeData.ModulesPath  -Destination "\\$NodeName\C$\Program Files\WindowsPowerShell\" -Recurse  -Force -PassThru #-Verbose
    }
}


# Complies MOF Files based on all nodes defined in psd configuration data file. MOF files are placed in "DSCConfig" folder in script folder
SCOMSetup -ConfigurationData .\SCOMSetupData.psd1 

# Pushes and starts all MOF Files to all nodes. 
# Use -ComputerName parameter if yo you want to push/start specific node
Start-DscConfiguration -Path 'SCOMSetup' -Wait -Verbose -Force #-ComputerName VS202

#$ConfigurationData = Import-PowerShellDataFile .\SCOMSetupData.psd1  
#$BasePath = $ConfigurationData.NonNodeData.ManagementPacksPath
#$MPList = Get-ChildItem $BasePath -Recurse -Name "*mp*"
#$MPList | ForEach-Object {
#      $file= $_
#      $ManagementPack = $BasePath + $file
#      Write-Host $ManagementPack
#      If (Test-Path ("$ManagementPack"))
#      {
#         Import-Module OperationsManager
#         Import-SCManagementPack $ManagementPack 
#      }
# }