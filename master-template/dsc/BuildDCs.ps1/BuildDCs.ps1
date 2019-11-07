configuration BuildDCs
{
   param
   (
        [string]$ConfigData,

        
        
        [String]$NodeName,
        
        [String]$site,
        [Boolean]$Primary = $false,
        [Boolean]$FileShare = $false,

        [Parameter(Mandatory=$true)]
		[ValidateNotNullorEmpty()]
        [PSCredential]
        $DomainAdminCredential,

        [PSCredential]
        $AzureShareCredential,

        [String]$DiskSize = "Small-4GB",
        [String]$DisksizeGB = 4,
        [String]$DataDisks, 
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
    
    # import DSC modules 
    Import-DscResource -ModuleName xActiveDirectory
    Import-DscResource -ModuleName ComputerManagementDsc  
    Import-DscResource -ModuleName xDnsServer      
    Import-DSCResource -ModuleName StorageDsc
    Import-DscResource -ModuleName XSmbShare
    Import-DscResource -ModuleName xPendingReboot
    Import-DscResource -ModuleName NetworkingDsc 
    Import-DscResource -ModuleName PSDesiredStateConfiguration

    # get computer network interface 
    $Interface=Get-NetAdapter|Where Name -Like "Ethernet*"|Select-Object -First 1
    $InterfaceAlias=$($Interface.Name)
    
    Node localhost
    {        
        # Convert Json string to Hashtable
        $ConfigData = $ConfigData | ConvertFrom-Json
        
        # Domain Settings
        $DomainName = $ConfigData.DomainName
        $DomainNetbiosName = $ConfigData.DomainNetbiosName
        $DNSServer  = $ConfigData.PrimaryDns
        $ForestMode = $ConfigData.ForestMode

        $sites = $ConfigData.sites
        $users = $ConfigData.DomainUsers
        $groups = $ConfigData.DomainGroups

        ################################
        # LCM SETTINGS 
        ################################
        # set local configuratiom manager settings 

        LocalConfigurationManager
        {
           RebootNodeIfNeeded = $RebootNodeIfNeeded
           ActionAfterReboot = $ActionAfterReboot            
           ConfigurationModeFrequencyMins = $ConfigurationModeFrequencyMins
           ConfigurationMode = $ConfigurationMode
           RefreshMode = $RefreshMode
           RefreshFrequencyMins = $RefreshFrequencyMins            
        }

        ################################
        # PREPARE VM
        ################################

        # Move DVD optical drive letter E to Z
        OpticalDiskDriveLetter MoveDiscDrive
        {
            DiskId      = 1
            DriveLetter = 'Z' # This value is ignored if absent
            Ensure      = 'Present'
        }
       
        # convert DataDisks Json string to array of objects
        $DataDisks = $DataDisks | ConvertFrom-Json        

        # loop each Datadisk information and mount to a letter in object
        $count = 2 # start with "2" ad "0" and "1" is for  C  and D that comes from WindowsServer Azure image 

        if($DataDisks.Count -gt 0){
            # if size eq small wait only one data disk
            if($DiskSize -ne "Default") {
                # wait for disk is mounted to vm and available   
                WaitForDisk DataDisk
                {
                    DiskId = $count 
                    RetryIntervalSec = $RetryIntervalSec
                    RetryCount = $RetryCount
                    #DependsOn  ="[OpticalDiskDriveLetter]MoveDiscDrive"
                }

                #$DependsOn = "[WaitForDisk]DataDisk"
            }

            $DisksizeGB  = [int64]$DisksizeGB * 1GB
        }

        foreach ($datadisk in $DataDisks)
        {
            if($DiskSize -ne "Default") {
                # once disk number availabe, assign and format drive with all available sizes and assign a leter and label that comes from parameters.
                if(($DataDisks.Length -1 ) -eq $DataDisks.IndexOf($datadisk))
                {
                    Disk $datadisk.letter
                    {
                        FSLabel = $datadisk.name
                        DiskId = $count 
                        DriveLetter = $datadisk.letter                  
                        #DependsOn = $DependsOn
                    }
                }                
                else {
                    Disk $datadisk.letter
                    {
                        FSLabel = $datadisk.name
                        DiskId = $count 
                        DriveLetter = $datadisk.letter
                        Size = $DisksizeGB
                        #DependsOn = $DependsOn
                    }
                }
                #$DependsOn = "[Disk]" + $datadisk.letter

                $DisksizeGB += 0.01GB
            }
            else{
                # wait for disk is mounted to vm and available   
                WaitForDisk $datadisk.name
                {
                    DiskId = $count 
                    RetryIntervalSec = $RetryIntervalSec
                    RetryCount = $RetryCount
                    #DependsOn  ="[OpticalDiskDriveLetter]MoveDiscDrive"                   
                }
                # once disk number availabe, assign and format drive with all available sizes and assign a leter and label that comes from parameters.
                Disk $datadisk.letter
                {
                    FSLabel = $datadisk.name
                    DiskId = $count 
                    DriveLetter = $datadisk.letter
                    #DependsOn = "[WaitForDisk]"+$datadisk.name
                }
                $count ++
            }
        }  
          
        ################################
        # DOMAIN SETUP
        ################################

        # install features for Domain Controllers
        # active directory windows features 

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
        
        # dns windows features 
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

        # Disable Firewall in each server
        Script DisableFirewall 
        {
            GetScript = {
                @{
                    GetScript = $GetScript
                    SetScript = $SetScript
                    TestScript = $TestScript
                    Result = -not('True' -in (Get-NetFirewallProfile -All).Enabled)
                }
            }

            SetScript = {
                Set-NetFirewallProfile -All -Enabled False -Verbose
                #Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False -Verbose
                
            }

            TestScript = {
                $Status = -not('True' -in (Get-NetFirewallProfile -All).Enabled)
                $Status -eq $True
            }
        }

        # modify computer dns 
        DnsServerAddress DnsServerAddress
        {
           Address        = $DNSServer
           InterfaceAlias = $InterfaceAlias
           AddressFamily  = 'IPv4'
        }
        # Region Prepare Domain
        if($Primary) { 
        # create domain first controller
        xADDomain FirstDS
        {
           DomainName                       = $DomainName
           #DomainNetbiosName               = $DomainNetbiosName
           DomainAdministratorCredential    = $DomainAdminCredential
           SafemodeAdministratorPassword    = $DomainAdminCredential
           ForestMode                       = $ForestMode
           DatabasePath                     = "E:\NTDS"
           LogPath                          = "E:\NTDS"
           SysvolPath                       = "E:\SYSVOL"
           #DependsOn = "[WindowsFeature]Feature-AD-Domain-Services", "[Disk]E"                       
        }
        
        $FarmTask  = "[xADDomain]FirstDS"
        
        foreach ($group in $groups)  
        {
            <#
            xADGroup "group-$group"
            {
                GroupName   = $group.GroupName
                GroupScope  = $group.GroupScope
                Category    = $group.Category
                Description = $group.Description
                Ensure      = 'Present'
            }
            #>
        }

        ############         
        # Create Domain Users 
        ##############
        foreach ($user in $users)  
        {
            $UserName = $user.UserName
            xADUser "User-$UserName"
            {
                Ensure     = 'Present'
                UserName   = $UserName
                Password   = $DomainAdminCredential
                DomainName = $DomainName
                PasswordNeverResets = $true
                Path       = "CN=Users,DC=$($DomainName.split('.')[0]),DC=$($DomainName.split('.')[1])"
                DependsOn         =  $FarmTask
            }
            
            $FarmTask  = "[xADUser]User-$UserName"
             
            $DomainGroups = $user.DomainGroups            

            $DomainGroups | ForEach-Object -Process {
                $GroupName = $_.Replace(" ", "")
                xADGroup "GroupAdd-$UserName-$GroupName"
                {
                   GroupName         =  $_                   
                   MembersToInclude  =  $UserName
                   Credential        =  $DomainAdminCredential
                   DependsOn         =  $FarmTask
                }
                $FarmTask  = "[xADGroup]GroupAdd-$UserName-$GroupName"
            }
        }

        # xADGroup "GroupAdd-Operators"
        # {                    
        #     GroupName         =  "Account Operators"                   
        #     MembersToInclude  =  "user_a"                      
        #     Credential        =  $DomainAdminCredential
        #     DependsOn         =  $FarmTask
        # }
        # $FarmTask  = "[xADGroup]GroupAdd-Operators"

        # Create Domain groups

        # Create sites and subnets to primary domain
        foreach ($site in $sites)         
        {
            xADReplicationSite $site.name 
            {
                Ensure      = "Present"
                Name        = $site.name
                RenameDefaultFirstSiteName = $true 
                #DependsOn="[xADDomain]FirstDS"        
            }
            
            xADReplicationSubnet $site.name
            {
                Ensure  = "Present"
                Name    = $site.prefix
                Site    = $site.name
                #DependsOn = "[xADReplicationSite]"+$site.name
            }
        }
   
        # create site links to primary domain
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
                    #DependsOn = "[xADReplicationSite]" + $site.name
                }
            }
        }

        # Domain Trust
        if ($DomainName -eq 'DomainDmz.com'){

            xDnsServerForwarder SetForwarders
            {
                IsSingleInstance = 'Yes'
                IPAddresses = '10.0.1.5'
            }

            $TargetDomainAdminCredential  =  New-Object -TypeName PSCredential -ArgumentList "Domain\domainadmin", $DomainAdminCredential.Password

            xADDomainTrust trust
            {
                Ensure                              = 'Present'
                SourceDomainName                    = $DomainName
                TargetDomainName                    = "Domain.com" #$TargetDomain
                TargetDomainAdministratorCredential = $TargetDomainAdminCredential
                TrustDirection                      = 'Outbound'
                TrustType                           = 'External'
              
            }
        }     
        
        if($FileShare) {    
            # copy share files from Azure to F:\share
            if($AzureShareCredential -ne $null -And $SourcePath -ne $null) {           

                File DirectoryCopy
                {
                    Ensure          = "Present"  # You can also set Ensure to "Absent"
                    Type            = "Directory" # Default is "File".
                    Recurse         = $true # Ensure presence of subdirectories, too
                    SourcePath      = $SourcePath
                    DestinationPath = "F:\SHARE"
                    Credential      = $AzureShareCredential
                    Force           =  $true
                    MatchSource     =  $true
                    #DependsOn      = "[xADDomain]FirstDS", "[Disk]F"
                }   
                # share folder to everyone as read access
                xSmbShare FileShare
                {
                    Ensure         = "Present"
                    Name           = "Share"
                    Path           = "F:\SHARE"
                    Description    = "This is a test SMB Share"
                    FullAccess     = 'Everyone'                   
                    DependsOn     = "[File]DirectoryCopy"
                }        
                # New SmbShare in ComputerManagementDSC
                # SmbShare 'FileShare'
                # {
                #     Ensure          = "Present"
                #     Name            = 'Share'
                #     Path            = 'F:\Share'
                #     Description     = 'File Share for binaries, Azure Share syncs'
                #     FullAccess = @('Everyone')
                #     DependsOn     = "[File]DirectoryCopy"
                #     #ConcurrentUserLimit = 20
                #     #EncryptData = $false
                #     #FolderEnumerationMode = 'AccessBased'
                #     #CachingMode = 'Manual'
                #     #ContinuouslyAvailable = $false
                # }
            }
            
            # File SQLAGBackup
            File SQLAGBackup
            {
                Ensure = "Present"  # You can also set Ensure to "Absent"
                Type = "Directory" # Default is "File". 
                DestinationPath = "F:\SQLAGBackup"
                Credential = $DomainAdminCredential
                #Force =  $true
                #DependsOn = "[Disk]F"
            }
    
            # xSmbShare MySMBShare
            xSmbShare SQLAGBackup
            {
                Ensure = "Present"
                Name   = "SQLAGBackUp"
                Path = "F:\SQLAGBackUp"
                Description = "This is for SQL AG temporary recovery/initilize location"
                FullAccess = 'Everyone'       
                #DependsOn = "[File]SQLAGBackup"                   
            }
        }
    }
    else {
        ## If Secondary Domain
        # wait primary domian is build and available
        xWaitForADDomain DscForestWait
        {
            DomainName = $DomainName
            #DomainUserCredential= $DomainAdminCredential
            RetryCount = $RetryCount
            RetryIntervalSec = $RetryIntervalSec                
        }

        # join computer to domian once domain is available
        Computer JoinDomain
        {
            Name       = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $DomainAdminCredential # Credential to join to domain
            #DependsOn  = "[xWaitForADDomain]DscForestWait"
        }

        # build this computer as replica domain controller
        xADDomainController  BDC
        {
            DomainName = $DomainName            
            DomainAdministratorCredential = $DomainAdminCredential
            SafemodeAdministratorPassword = $DomainAdminCredential
            DatabasePath = "E:\NTDS"
            LogPath = "E:\NTDS"
            SysvolPath = "E:\SYSVOL"              
            SiteName   = $site
            #DependsOn  = "[Computer]JoinDomain", "[Disk]E"
        }
    }
    # end Prepare Domain

   }
}