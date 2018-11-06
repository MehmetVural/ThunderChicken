
Configuration DSCConfig {     

    Node $AllNodes.NodeName   {
             
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
 