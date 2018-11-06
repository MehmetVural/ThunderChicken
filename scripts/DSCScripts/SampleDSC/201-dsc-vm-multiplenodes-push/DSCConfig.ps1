
Configuration DSCConfig {  
  
    #Basic DSC Operation Module. Not Required not removes warning. 
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'

    Node $AllNodes.NodeName  {

        # This section contains settings for the LCM        
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
        }

        Script AddContent 
        {
            TestScript = { 
                Test-Path 'C:\test.txt' 
            }
            SetScript = {
                    Add-Content 'C:\test.txt' 'Hello DSC World!.'
            }
            GetScript = {$null}
        }          
    }

    Node ($AllNodes.Where{$_.Role -eq "WebServer"}).NodeName
    {            
        # Windows Feature - Web Server       
        WindowsFeature IIS {
            Ensure               = 'Present'
            Name                 = 'Web-Server'
            IncludeAllSubFeature = $true
        }   
    }
}
 