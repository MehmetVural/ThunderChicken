configuration ProvisionReplicaDCs
{
   param
   (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [String]$DNSServer,

        [Parameter(Mandatory=$true)]
		[ValidateNotNullorEmpty()]
		[PSCredential]$DomainAdminCredential,
        
        [Int]$RetryCount=40,
        [Int]$RetryIntervalSec=30
    )

    Import-DscResource -ModuleName xActiveDirectory
    Import-DscResource -ModuleName xNetworking
    Import-DscResource -ModuleName ComputerManagementDsc    
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

        xDnsServerAddress DnsServerAddress
        {
            Address        = $DNSServer
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
            DependsOn="[WindowsFeature]Feature-AD-Domain-Services"
        }

        xWaitForADDomain DscForestWait
        {
            DomainName = $DomainName
            #DomainUserCredential= $DomainAdminCredential
            RetryCount = $RetryCount
            RetryIntervalSec = $RetryIntervalSec
            DependsOn  = "[xDnsServerAddress]DnsServerAddress"
        }

        Computer JoinDomain
        {
            Name       = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $DomainAdminCredential # Credential to join to domain
            DependsOn  = "[xDnsServerAddress]DnsServerAddress"
        }
         
        xADDomainController  BDC
        {
            DomainName = $DomainName            
            DomainAdministratorCredential = $DomainAdminCredential
            SafemodeAdministratorPassword = $DomainAdminCredential
            DatabasePath = "C:\NTDS"
            LogPath = "C:\NTDS"
            SysvolPath = "C:\SYSVOL"
            SiteName   = 'CS'
            DependsOn  = "[Computer]JoinDomain"

        }        
   }
}