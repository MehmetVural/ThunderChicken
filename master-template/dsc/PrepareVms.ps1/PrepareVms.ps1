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
        [String]$ConfigurationMode = "ApplyAndAutoCorrect",
        [String]$RefreshMode = "Push",
        [String]$RefreshFrequencyMins  = 30
    )

    # import DSC modules 
    Import-DscResource -ModuleName xActiveDirectory
    Import-DscResource -ModuleName ComputerManagementDsc  
    Import-DSCResource -ModuleName StorageDsc
    Import-DscResource -ModuleName xPendingReboot
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
           DependsOn = "[Computer]JoinDomain"
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

             
   }
}