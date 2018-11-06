
Configuration DSCConfig { 
    
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'       

    Node $AllNodes.NodeName  {
        
        # Add txt File    
        if ($Node.CopyFiles) {
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
 