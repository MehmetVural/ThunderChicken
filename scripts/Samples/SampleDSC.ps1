
$ConfigurationData = @{
    AllNodes =
       @(
           @{
               NodeName = "blank-vs-vm1"
               PSDscAllowPlainTextPassword = $true
               PsDscAllowDomainUser= $true
           },
   
   
           @{
               NodeName = "blank-ks-vm1"
               PSDscAllowPlainTextPassword = $true
               PsDscAllowDomainUser = $true
           },
   
   
           @{
               NodeName = "blank-cs-vm1"
               PSDscAllowPlainTextPassword = $true
               PsDscAllowDomainUser = $true
           }
       );
   
       NonNodeData = ""    
   
   }
   
   #Get files from Azure file share
   $acctKey = ConvertTo-SecureString -String "ayuRXkvhNu7AQYXHKmwmP4xaZ03/rENNaHaZEWVcJiHIMTIyHBN8MBfGd7i4jZ7JG0PZM5YqN8JyNNJ9ovRHzQ==" -AsPlainText -Force
   $credential = New-Object System.Management.Automation.PSCredential -ArgumentList "Azure\share4d0128a7e677478d88d", $acctKey
   $sourcepath = "\\share4d0128a7e677478d88d.file.core.windows.net\share"   

   configuration SampleDSC
   {
      param
      (
          
       )
   
       Import-DscResource -ModuleName xDisk, cDisk  
       Import-DscResource -ModuleName PSDesiredStateConfiguration
   
       Node $AllNodes.NodeName
       {
           LocalConfigurationManager
           {
               ConfigurationMode = "ApplyAndAutocorrect"
               RebootNodeIfNeeded = $true
               RefreshMode = "Push"
               
               
           }
   
           xWaitforDisk Disk2
           {
                DiskNumber = 2
                RetryIntervalSec =$RetryIntervalSec
                RetryCount = $RetryCount
           }
           
           cDiskNoRestart FSDataDisk
           {
               DiskNumber = 2
               DriveLetter = "F"
               DependsOn="[xWaitForDisk]Disk2"
           }          
   
           File DirectoryCopy
           {
               Ensure = "Present"  # You can also set Ensure to "Absent"
               Type = "Directory" # Default is "File".
               Recurse = $true # Ensure presence of subdirectories, too
               SourcePath = $sourcepath
               Credential = $credential
               DestinationPath = "F:\INSTALL"
               DependsOn = "[cDiskNoRestart]FSDataDisk"
           }   
      }
   }
   
   SampleDSC -ConfigurationData $ConfigurationData
   
   Start-DSCconfiguration -Path "SampleDSC" -wait -verbose -Force