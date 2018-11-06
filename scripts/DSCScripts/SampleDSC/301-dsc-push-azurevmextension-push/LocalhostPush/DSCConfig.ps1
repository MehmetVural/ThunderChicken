
Configuration DSCConfig1 {  
    
    Node Localhost  {
      
         # This section contains settings for the LCM        
         LocalConfigurationManager
         {
             RebootNodeIfNeeded = $true
         }

         Script AddContent 
         {
             TestScript = { 
                 Test-Path 'C:\test-test.txt' 
             }
             SetScript = {
                     Add-Content 'C:\test-test.txt' 'Hello DSC World!.'
             }
             GetScript = {$null}
         }  
       
        
    }

  
}
 