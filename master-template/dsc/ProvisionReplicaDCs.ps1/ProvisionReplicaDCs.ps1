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
           DriveLetter = 'Z' # This value is ignored
           Ensure      = 'Present'
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
        $count = 2 # start with "2" ad "0" and "1" is for  C  and D that comes from WindowsServer Azure image 
        
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