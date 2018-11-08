
Configuration DSCConfig {  
    
    Node Localhost {
      
        # This section contains settings for the LCM        
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
        }

        Script AddContent {
            TestScript = { 
                Test-Path 'C:\301-test.txt' 
            }
            SetScript  = {
                Add-Content 'C:\301-test.txt' 'Hello DSC World!.'
            }
            GetScript  = {$null}
        }  

        # Windows Feature - Web Server       
        WindowsFeature IIS {
            Ensure               = 'Present'
            Name                 = 'Web-Server'
            IncludeAllSubFeature = $true
        }  
       
        
    }

  
}
 