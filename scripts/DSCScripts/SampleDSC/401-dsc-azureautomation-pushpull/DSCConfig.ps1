
Configuration DSCConfig { 
    
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'       

    Node $AllNodes.NodeName  {
        
        # Add txt File    
        if ($Node.CopyFiles) {
            Script AddContent 
            {
                TestScript = { 
                    Test-Path 'C:\401-test.txt' 
                }
                SetScript = {
                        Add-Content 'C:\401-test.txt' 'Hello DSC World!.'
                }
                GetScript = {$null}
            } 
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
 