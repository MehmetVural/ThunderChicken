
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
                Test-Path 'C:\101-test.txt' 
            }
            SetScript = {
                    Add-Content 'C:\101-test.txt' 'Hello DSC World!.'
            }
            GetScript = {$null}
        }    
    }
}
 