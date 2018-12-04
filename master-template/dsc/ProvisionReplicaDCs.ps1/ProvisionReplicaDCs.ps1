configuration ProvisionReplicaDCs
{
   param
   (
        [Parameter(Mandatory)]
        [String]$DomainName,        

        [Parameter(Mandatory)]
        [String]$DNSServer,

        [string]$DataDisks,

        [Parameter(Mandatory)]
        [String]$site,

        [Parameter(Mandatory=$true)]
		[ValidateNotNullorEmpty()]
		[PSCredential]$DomainAdminCredential,
        
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
            RebootNodeIfNeeded = $RebootNodeIfNeeded
            ActionAfterReboot = $ActionAfterReboot            
            ConfigurationModeFrequencyMins = $ConfigurationModeFrequencyMins
            ConfigurationMode = $ConfigurationMode
            RefreshMode = $RefreshMode
            RefreshFrequencyMins = $RefreshFrequencyMins            
        }

        
        # remove D drive as system managed drive. and place paging files to C drive. 
        $computer = Get-WmiObject Win32_computersystem -EnableAllPrivileges
        $computer.AutomaticManagedPagefile = $false
        $computer.Put()
        $CurrentPageFile = Get-WmiObject -Query "select * from Win32_PageFileSetting where name='d:\\pagefile.sys'"       
        if($CurrentPageFile -ne $null) { $CurrentPageFile.delete() }
        Set-WMIInstance -Class Win32_PageFileSetting -Arguments @{name="c:\pagefile.sys";InitialSize = 0; MaximumSize = 0} -ErrorAction SilentlyContinue
         
        # remove dummy txt file that azure places. 
        File RemoveReadMe
        {
             DestinationPath = "D:\DATALOSS_WARNING_README.txt"
             Ensure = "Absent"
             Type = "File"
             Force = $true
        }

        # move DVD optical drive to Z letter, empty "E"
       OpticalDiskDriveLetter RemoveDiscDrive
       {
           DiskId      = 1
           DriveLetter = 'Z' # This value is ignored
           Ensure      = 'Present'
       }  

        # change C drive label "System" from "Windows"
        $drive = gwmi win32_volume -Filter "DriveLetter = 'C:'"
        $drive.Label = "System"
        $drive.put()
        # change D drive label to "Local Data" from "Temporary Data"
        $drive = gwmi win32_volume -Filter "DriveLetter = 'D:'"
        $drive.Label = "Local Data"
        $drive.put()
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

        DnsServerAddress DnsServerAddress
        {
            Address        = $DNSServer
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'           
        }

        xWaitForADDomain DscForestWait
        {
            DomainName = $DomainName
            #DomainUserCredential= $DomainAdminCredential
            RetryCount = $RetryCount
            RetryIntervalSec = $RetryIntervalSec          
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
            DatabasePath = "E:\NTDS"
            LogPath = "E:\NTDS"
            SysvolPath = "E:\SYSVOL"              
            SiteName   = $site
            DependsOn  = "[Computer]JoinDomain"
        }        
   }
}