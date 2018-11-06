
Configuration DSCConfig {  

    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'

    Node Localhost {                
        # Windows Feature - Web Server       
        WindowsFeature IIS {
            Ensure               = 'Present'
            Name                 = 'Web-Server'
            IncludeAllSubFeature = $true
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
}
 