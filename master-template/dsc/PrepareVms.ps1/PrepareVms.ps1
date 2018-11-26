configuration PrepareVms
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
        
        [Parameter(Mandatory=$true)]
        [Int]$RetryCount,
        
        [Parameter(Mandatory=$true)]
        [Int]$RetryIntervalSec
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
        
        WaitForDisk Disk2
        {
             DiskId = 2
             RetryIntervalSec = $RetryIntervalSec
             RetryCount = $RetryCount            
        }

        Disk FVolume
        {
             DiskId = 2
             DriveLetter = 'F'           
             DependsOn = '[WaitForDisk]Disk2'
        }
   
        DnsServerAddress  DnsServerAddress
        {
            Address        = $DNSServer
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'                  
        }       

        xWaitForADDomain DscForestWait
        {
            DomainName = $DomainName
            DomainUserCredential= $DomainAdminCredential
            RetryCount = $RetryCount
            RetryIntervalSec = $RetryIntervalSec
            DependsOn  = "[DnsServerAddress]DnsServerAddress"
        }

        Computer JoinDomain
        {
            Name       = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $DomainAdminCredential 
            DependsOn  = "[xWaitForADDomain]DscForestWait"
        }       
   }
}