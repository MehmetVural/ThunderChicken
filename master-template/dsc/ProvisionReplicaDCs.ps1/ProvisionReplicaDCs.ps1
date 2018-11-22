configuration ProvisionReplicaDCs
{
   param
   (
        [Parameter(Mandatory)]
        [String]$DomainName,        

        [Parameter(Mandatory)]
        [String]$DNSServer,

        [Parameter(Mandatory)]
        [String]$site,

        [Parameter(Mandatory=$true)]
		[ValidateNotNullorEmpty()]
		[PSCredential]$DomainAdminCredential,
        
        [Int]$RetryCount=40,
        [Int]$RetryIntervalSec=30
    )

    Import-DscResource -ModuleName xActiveDirectory
    Import-DscResource -ModuleName ComputerManagementDsc  
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

        #Registry DisableIPv6
        #{
        #    Key       = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
        #    ValueName = "DisabledComponents"
        #    ValueData = "ff"
        #    ValueType = "Dword"
        #    Hex       = $true
        #    Ensure    = 'Present'
        #}

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
             RetryIntervalSec = 60
             RetryCount = 60
             DependsOn="[WindowsFeature]Feature-AD-Domain-Services"
        }

        Disk FVolume
        {
             DiskId = 2
             DriveLetter = 'F'           
             DependsOn = '[WaitForDisk]Disk2'
        }

        DnsServerAddress DnsServerAddress
        {
            Address        = $DNSServer
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
            DependsOn="[Disk]FVolume"
        }

        xWaitForADDomain DscForestWait
        {
            DomainName = $DomainName
            #DomainUserCredential= $DomainAdminCredential
            RetryCount = $RetryCount
            RetryIntervalSec = $RetryIntervalSec
            DependsOn  = "[DnsServerAddress]DnsServerAddress"
        }

        Computer JoinDomain
        {
            Name       = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $DomainAdminCredential # Credential to join to domain
            DependsOn  = "[xWaitForADDomain]DscForestWait"
        }
         
        xADDomainController  BDC
        {
            DomainName = $DomainName            
            DomainAdministratorCredential = $DomainAdminCredential
            SafemodeAdministratorPassword = $DomainAdminCredential
            DatabasePath = "F:\NTDS"
            LogPath = "F:\NTDS"
            SysvolPath = "F:\SYSVOL"
            SiteName   = $site
            DependsOn  = "[Computer]JoinDomain"
        }        
   }
}