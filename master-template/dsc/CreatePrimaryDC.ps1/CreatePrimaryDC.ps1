configuration CreatePrimaryDC
{
   param
   (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [String]$DomainNetbiosName, 
        
        [Parameter(Mandatory)]
        [String]$DNSServer, 
       
        [String]$DataDisks,

        [Parameter(Mandatory)]
        [String]
        $sites,

        [Parameter(Mandatory)]
        [String]$ForestMode,       

        [Parameter(Mandatory=$true)]
		[ValidateNotNullorEmpty()]
        [PSCredential]$DomainAdminCredential,
              
        [PSCredential]$AzureShareCredential,
       
        [String]$SourcePath,

        [Parameter(Mandatory=$true)]
        [Int]$RetryCount,
        
        [Parameter(Mandatory=$true)]
        [Int]$RetryIntervalSec,

        [Boolean]$RebootNodeIfNeeded = $true,
        [String]$ActionAfterReboot = "ContinueConfiguration",
        [String]$ConfigurationModeFrequencyMins = 15,
        [String]$ConfigurationMode = "ApplyAndMonitor",
        [String]$RefreshMode = "Push",
        [String]$RefreshFrequencyMins  = 30

    )

    Import-DscResource -ModuleName xActiveDirectory    
    Import-DSCResource -ModuleName StorageDsc
    Import-DscResource -ModuleName XSmbShare
    Import-DscResource -ModuleName xPendingReboot
    Import-DscResource -ModuleName NetworkingDsc 
    Import-DscResource -ModuleName PSDesiredStateConfiguration

    $Interface=Get-NetAdapter|Where Name -Like "Ethernet*"|Select-Object -First 1
    $InterfaceAlias=$($Interface.Name)
    
    Node localhost
    {
        LocalConfigurationManager
        {
           RebootNodeIfNeeded = $RebootNodeIfNeeded
           ActionAfterReboot = $ActionAfterReboot            
           ConfigurationModeFrequencyMins = $ConfigurationModeFrequencyMins
           ConfigurationMode = $ConfigurationMode
           RefreshMode = $RefreshMode
           RefreshFrequencyMins = $RefreshFrequencyMins            
        }

        # change C drive label to "System" from "Windows"
        $drive = Get-WmiObject win32_volume -Filter "DriveLetter = 'C:'"
        $drive.Label = "System"
        $drive.put()

       # remove DVD optical drive
       OpticalDiskDriveLetter RemoveDiscDrive
       {
         DiskId      = 1
         DriveLetter = 'E' # This value is ignored
         Ensure      = 'Absent'
       }  
      
       # removes pagefile on Drive and move D drive to T and sets back page file on that drive
       Script DeletePageFile
       {
          SetScript = {
              
              #Get-WmiObject win32_pagefilesetting
              $pf = Get-WmiObject win32_pagefilesetting
              if($pf -ne $null) {$pf.Delete()}               
          }

          TestScript = {                                 
              $CurrentPageFile = Get-WmiObject -Query "select * from Win32_PageFileSetting where name='T:\\pagefile.sys'"       
              if($CurrentPageFile -eq $null) { return $false } else {return $true }
          }
          GetScript = { $null } 
          DependsOn = "[OpticalDiskDriveLetter]RemoveDiscDrive"           
      }

      xPendingReboot Reboot1
      {
          name = "After deleting PageFile"
      }

       # removes pagefile on Drive and move D drive to T and sets back page file on that drive
      Script DDrive
      {
           SetScript = {
               $TempDriveLetter = "T"

               # move D Temporary Data drive  drive to T
               $drive = Get-Partition -DriveLetter "D" | Set-Partition -NewDriveLetter $TempDriveLetter

               #set pagefile to T drive 
               $TempDriveLetter = $TempDriveLetter + ":"
               Set-WMIInstance -Class Win32_PageFileSetting -Arguments @{ Name = "$TempDriveLetter\pagefile.sys"; MaximumSize = 0; }
           }

           TestScript = {                                 
               $CurrentPageFile = Get-WmiObject -Query "select * from Win32_PageFileSetting where name='T:\\pagefile.sys'"       
               if($CurrentPageFile -eq $null) { return $false } else {return $true }
           }
           GetScript = { $null } 
           DependsOn = "[xPendingReboot]Reboot1"           
       }
        
        
        # convert DataDisks Json string to array of objects
        $DataDisks = $DataDisks | ConvertFrom-Json        

        # loop each Datadisk information and mount to a letter in object
        $count = 2 # start with "2" and "0" and "1" is for  C  and D that comes from WindowsServer Azure image 
        
        foreach ($datadisk in $DataDisks)         
        {
            # wait for disk is mounted to vm and available   
            WaitForDisk $datadisk.name
            {
                DiskId = $count 
                RetryIntervalSec = $RetryIntervalSec
                RetryCount = $RetryCount
                DependsOn  ="[Script]DDrive" 
            }
            # once disk number availabe, assign and format drive with all available sizes and assign a leter and label that comes from parameters.
            Disk $datadisk.letter
            {
                FSLabel = $datadisk.name
                DiskId = $count 
                DriveLetter = $datadisk.letter
                DependsOn = "[WaitForDisk]"+$datadisk.name
            }

            $count ++
        }       
        
        # install features
        @(
            "DNS",
            "RSAT-Dns-Server"
        ) | ForEach-Object -Process {
            WindowsFeature "Feature-$_"
            {
                Ensure = "Present"
                Name = $_
            }
        }

        @(
            "AD-Domain-Services",            
            "RSAT-ADDS-Tools"                                         
        ) | ForEach-Object -Process {
            WindowsFeature "Feature-$_"
            {
                Ensure = "Present"
                Name = $_
            }
        }

        # modify dns 
        DnsServerAddress DnsServerAddress
        {
            Address        = $DNSServer
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'	    
        }
        
         # create domain
        xADDomain FirstDS
        {
            DomainName      = $DomainName
            DomainNetbiosName = $DomainNetbiosName
            DomainAdministratorCredential = $DomainAdminCredential
            SafemodeAdministratorPassword = $DomainAdminCredential
            ForestMode                    = $ForestMode
            DatabasePath = "E:\NTDS"
            LogPath = "E:\NTDS"
            SysvolPath = "E:\SYSVOL"
            DependsOn="[WindowsFeature]Feature-AD-Domain-Services"                       
        }

        # create sites and subnets to domain
        $sites = $sites | ConvertFrom-Json 

        foreach ($site in $sites)         
        {
            xADReplicationSite $site.name 
            {
                Ensure = "Present"
                Name = $site.name
                RenameDefaultFirstSiteName = $true       
            }
            xADReplicationSubnet $site.name
            {
                Ensure = "Present"
                Name   = $site.prefix
                Site  = $site.name
                DependsOn = "[xADReplicationSite]"+$site.name
            }
        }

        # create site links to domain
        foreach ($site in $sites)         
        {
            if($site.sitelink -ne $null)
            {
                $linkname = $site.sitelink.Replace(',', ' to ')
                $name = $site.name
                $sitelink  = $site.sitelink.Split(',')

                Script "ADReplicationSiteLink-$name"
                {
                    SetScript = {
                        New-ADReplicationSiteLink -Name $using:linkname -SitesIncluded $using:sitelink -Cost 100 -ReplicationFrequencyInMinutes 15 -InterSiteTransportProtocol IP
                        Get-ADReplicationSiteLink -filter {Name -eq "DEFAULTIPSITELINK"} | Remove-ADReplicationSiteLink
                    }

                    TestScript = { 
                            $site = Get-ADReplicationSiteLink -filter {Name -eq $using:linkname}
                            if($site -eq $null) 
                            {
                                return $false
                            }
                            else 
                            {
                                return $true
                            }
                     }
                    GetScript = { $null }
                    DependsOn = "[xADReplicationSite]" + $site.name
                }
            }

        }
        # copy share files from Azure
        if($AzureShareCredential -ne $null -And $SourcePath -ne $null) {
            File DirectoryCopy
            {
                Ensure = "Present"  # You can also set Ensure to "Absent"
                Type = "Directory" # Default is "File".
                Recurse = $true # Ensure presence of subdirectories, too
                SourcePath = $SourcePath
                DestinationPath = "F:\SHARE"
                Credential = $AzureShareCredential
                Force =  $true
                MatchSource =  $true
                DependsOn = "[xADDomain]FirstDS"
            }

            xSmbShare MySMBShare
            {
                Ensure = "Present"
                Name   = "Share"
                Path = "F:\SHARE"
                Description = "This is a test SMB Share"
                ReadAccess = 'Everyone'
                DependsOn = "[File]DirectoryCopy"
                
            }
        }
        
   }
}