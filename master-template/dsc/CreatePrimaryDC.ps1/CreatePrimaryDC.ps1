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

        [Parameter(Mandatory)]
        [string]
        $sites,

        [Parameter(Mandatory)]
        [String]$ForestMode,       

        [Parameter(Mandatory=$true)]
		[ValidateNotNullorEmpty()]
		[PSCredential]$DomainAdminCredential,        

        
        [Parameter(Mandatory=$true)]
        [Int]$RetryCount,
        
        [Parameter(Mandatory=$true)]
        [Int]$RetryIntervalSec
    )

    Import-DscResource -ModuleName xActiveDirectory    
    Import-DSCResource -ModuleName StorageDsc
    Import-DscResource -ModuleName NetworkingDsc 
    Import-DscResource -ModuleName PSDesiredStateConfiguration

    $Interface=Get-NetAdapter|Where Name -Like "Ethernet*"|Select-Object -First 1
    $InterfaceAlias=$($Interface.Name)
    
    Node localhost
    {
        LocalConfigurationManager
        {
            ConfigurationMode = 'ApplyOnly'
            RebootNodeIfNeeded = $true
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
        
        WaitForDisk Disk2
        {
             DiskId = 2
             RetryIntervalSec   = $RetryIntervalSec
             RetryCount         = $RetryCount
             DependsOn          ="[WindowsFeature]Feature-AD-Domain-Services"
        }

        Disk FVolume
        {
             DiskId         = 2
             DriveLetter    = 'F'          
             DependsOn      = '[WaitForDisk]Disk2'
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
            DatabasePath = "F:\NTDS"
            LogPath = "F:\NTDS"
            SysvolPath = "F:\SYSVOL"
            DependsOn="[Disk]FVolume"
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
                TestScript = { $false }
                GetScript = { $null }
                DependsOn = "[xADReplicationSite]" + $site.name
                }
            }

        }
        
   }
}