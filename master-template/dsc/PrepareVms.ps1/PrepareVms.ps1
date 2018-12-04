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

        [string]$DataDisks,

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
    Import-DSCResource -ModuleName StorageDsc
    Import-DscResource -ModuleName NetworkingDsc
    Import-DscResource -ModuleName PSDesiredStateConfiguration

    # get network adapter interface name 
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

        # change DNS server address to subnet DNS address
        DnsServerAddress  DnsServerAddress
        {
            Address        = $DNSServer
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'                  
        }       

        # wait domain is available before joinning this computer to domain
        xWaitForADDomain DscForestWait
        {
            DomainName = $DomainName
            DomainUserCredential= $DomainAdminCredential
            RetryCount = $RetryCount
            RetryIntervalSec = $RetryIntervalSec
            DependsOn  = "[DnsServerAddress]DnsServerAddress"
        }

        # once domain is available join this computer to domain.
        Computer JoinDomain
        {
            Name       = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $DomainAdminCredential 
            DependsOn  = "[xWaitForADDomain]DscForestWait"
        }       
   }
}