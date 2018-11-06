# This Script complies MOF file for localhost and applies 
# RDP to VM, copy these files into a folder, run PushDSCtoLocalhost.ps1 file 

Push-Location (Split-Path -Path $MyInvocation.MyCommand.Definition -Parent)

. .\DSCConfig.ps1 

DSCConfig 

Start-DscConfiguration -Path 'DSCConfig' -Wait -Verbose -Force

