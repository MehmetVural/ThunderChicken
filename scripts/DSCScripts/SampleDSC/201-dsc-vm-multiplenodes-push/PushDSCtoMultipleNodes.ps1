# This Script complies MOF files for each computer and pushes configuration to all computers and applies configuration
# computers are defined in .\DSCConfigData.psd1 file 
# RDP to VM, copy these files into a folder, run PushDSCtoMultipleNodes.ps1 file 

Push-Location (Split-Path -Path $MyInvocation.MyCommand.Definition -Parent)

. .\DSCConfig.ps1 

# Complies MOF Files based on all nodes defined in psd configuration data file. MOF files are placed in "DSCConfig" folder in script folder
DSCConfig -ConfigurationData .\DSCConfigData.psd1 

# Pushes and starts all MOF Files to all nodes. 
# Use -ComputerName parapeter if yo you want to push/start specific node
Start-DscConfiguration -Path 'DSCConfig' -Wait -Verbose -Force 