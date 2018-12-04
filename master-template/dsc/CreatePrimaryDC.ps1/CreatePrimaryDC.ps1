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

        # remove DVD optical drive
        OpticalDiskDriveLetter RemoveDiscDrive
        {
           DiskId      = 1
           #DriveLetter = 'Z' # This value is ignored
           Ensure      = 'Absent'
        }  


        # remove D drive as system managed drive. and place paging files to C drive. 
        Script DDrive
        {
            SetScript = {

                # change C drive label "System" from "Windows"
                $drive = gwmi win32_volume -Filter "DriveLetter = 'C:'"
                $drive.Label = "System"
                $drive.put()

                # remove D drive as system managed drive. and place paging files to C drive. 
                $computer = Get-WmiObject Win32_computersystem -EnableAllPrivileges
                $computer.AutomaticManagedPagefile = $false
                $computer.Put()
                $CurrentPageFile = Get-WmiObject -Query "select * from Win32_PageFileSetting where name='d:\\pagefile.sys'"       
                if($CurrentPageFile -ne $null) { $CurrentPageFile.delete() }
                Set-WMIInstance -Class Win32_PageFileSetting -Arguments @{name="c:\pagefile.sys";InitialSize = 0; MaximumSize = 0} -ErrorAction SilentlyContinue
            }

            TestScript = { $false}
            GetScript = { $null } 
            DependsOn = "[OpticalDiskDriveLetter]RemoveDiscDrive"           
        }

        Disk DtoTVolume
        {
             DiskId = 1
             DriveLetter = 'T'             
             DependsOn = '[Script]DDrive'
        }  
         
         # move paging back to T drive.
         Script TPaging
         {
             SetScript = {
                 # remove D drive as system managed drive. and place paging files to C drive. 
                 $computer = Get-WmiObject Win32_computersystem -EnableAllPrivileges
                 $computer.AutomaticManagedPagefile = $false
                 $computer.Put()
                 $CurrentPageFile = Get-WmiObject -Query "select * from Win32_PageFileSetting where name='c:\\pagefile.sys'"       
                 if($CurrentPageFile -ne $null) { $CurrentPageFile.delete() }
                 Set-WMIInstance -Class Win32_PageFileSetting -Arguments @{name="T:\pagefile.sys";InitialSize = 0; MaximumSize = 0} -ErrorAction SilentlyContinue
             } 
             TestScript = { $false}
             GetScript = { $null } 
             DependsOn = "[Disk]DtoTVolume"                    
        }        
        
        # change D drive label to "Local Data" from "Temporary Data"
        #$drive = gwmi win32_volume -Filter "DriveLetter = 'D:'"
        #$drive.Label = "Local Data"
        #$drive.put()
        
        
        # convert DataDisks Json string to array of objects
        $DataDisks = $DataDisks | ConvertFrom-Json        

        # loop each Datadisk information and mount to a letter in object
        $count = 2 # start with "2" ad "0" and "1" is for  C  and D that comes from WindowsServer Azure image 
        
        foreach ($datadisk in $DataDisks)         
        {
            # wait for disk is mounted to vm and available   
            WaitForDisk $datadisk.name
            {
                DiskId = $count 
                RetryIntervalSec = $RetryIntervalSec
                RetryCount = $RetryCount
                DependsOn  ="[OpticalDiskDriveLetter]RemoveDiscDrive" 
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
       
        DnsServerAddress DnsServerAddress
        {
            Address        = $DNSServer
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'	    
        }
        
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
        
   }
}