try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction SilentlyContinue
}
catch 
{
  Write-Verbose "Successfully Updated"  
}


Configuration PrepareVms
{
   param
   (
        [String]$DiskSize = "Small-4GB",
        [String]$DisksizeGB = 4,

        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [String]$DomainNetbiosName,
        
        [Parameter(Mandatory)]
        [String]$DNSServer,

        [Boolean]$joinDomain = $false,
        
        [string]$ServiceName,
        [string]$ServerName,      
        [String]$ServerIP, 
        [String]$ServerSite, 

        [string]$ConfigData,
        
        #[Parameter(Mandatory=$true)]
		#[ValidateNotNullorEmpty()]
        #[PSCredential]$UserAdminCredential,
        
        [Parameter(Mandatory=$true)]
		[ValidateNotNullorEmpty()]
        [PSCredential]$LocalAdminCredential,

        [Parameter(Mandatory=$true)]
		[ValidateNotNullorEmpty()]
        [PSCredential]$InstallCredential,

        [Parameter(Mandatory=$true)]
		[ValidateNotNullorEmpty()]
        [PSCredential]$DomainAdminCredential,

        [string]$DataDisks,
        
        [Int]$RetryCount = 600,        
        [Int]$RetryIntervalSec = 60,

        [Boolean]$RebootNodeIfNeeded = $true,
        [String]$ActionAfterReboot = "ContinueConfiguration",
        [String]$ConfigurationModeFrequencyMins = 15,
        [String]$ConfigurationMode = "ApplyAndAutoCorrect",
        [String]$RefreshMode = "Push",
        [String]$RefreshFrequencyMins  = 30
    )

    # import DSC modules 
    Import-DscResource -ModuleName xActiveDirectory
    Import-DscResource -ModuleName ActiveDirectoryCSDsc
    Import-DscResource -ModuleName ComputerManagementDsc  
    #Import-DscResource -ModuleName PackageManagement    
    Import-DscResource -ModuleName xCredSSP
    Import-DscResource -ModuleName SqlServerDsc
    Import-DscResource -Module  xSCOM -ModuleVersion "1.3.3.1"
    Import-DSCResource -ModuleName StorageDsc
    Import-DscResource -ModuleName xPendingReboot
    Import-DscResource -ModuleName NetworkingDsc
    Import-DscResource -ModuleName xDnsServer
    Import-DscResource -ModuleName PSDesiredStateConfiguration    

    # get network adapter interface name 
    $Interface=Get-NetAdapter|Where Name -Like "Ethernet*"|Select-Object -First 1
    $InterfaceAlias=$($Interface.Name)
                        
    Node localhost
    {
        ## Region Parameters
        # Convert Json string to Hashtable        
        # $ConfigData | Out-File -FilePath C:\json.txt
        $ConfigData = $ConfigData | ConvertFrom-Json

        foreach ($myPsObject in $ConfigData) {
            $ConfigDataHash = @{};
            $myPsObject | Get-Member -MemberType *Property | % { $ConfigDataHash.($_.name) = $myPsObject.($_.name);  }
            $ConfigDataHash;                
        }
        
        $ConfigData =  $ConfigDataHash
        # $ConfigData | Out-File -FilePath C:\json.txt
        
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
       
        xCredSSP CredSSPServer
        {
            Ensure = 'Present'
            Role = 'Server'
        }

        xCredSSP CredSSPClient
        {
            Ensure = 'Present'
            Role = 'Client'
            DelegateComputers = '*.Domain.com'
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

        # Install RSAT tools  to each machine           
        @(
            "RSAT",
            "RSAT-ADDS-Tools",
            "RSAT-AD-PowerShell",
            "RSAT-DNS-Server",
            "RSAT-DHCP"
        ) | ForEach-Object -Process {
            WindowsFeature "Feature-$_"
            {
                Ensure = "Present"
                Name = $_                   
            }
        }


        if($joinDomain){           

            # change DNS server address to subnet DNS address
            DnsServerAddress  DnsServerAddress
            {
                Address        = $DNSServer
                InterfaceAlias = $InterfaceAlias
                AddressFamily  = 'IPv4'                  
            }   
        
            $FarmTask = "[DnsServerAddress]DnsServerAddress" 
        }


        if(-Not $joinDomain)
        {          
            Script SetWSMAN
            {
                SetScript = {
                    try {
                    Set-item wsman:\localhost\Client\TrustedHosts -value "*.domain.com" -ErrorAction SilentlyContinue 
                    Set-NetFirewallRule –Name "WINRM-HTTP-In-TCP-PUBLIC" –RemoteAddress Any
                    }
                    catch {
                    Write-Verbose "Something went wrong during setting Set-Item WSMAN "
                    }
                }
    
                TestScript = {                                 
                    return $false
                }
                GetScript = { $null }                
            }
    
            $FarmTask = "[Script]SetWSMAN"  

            <# 
            User LocalUserA
            {
                Ensure      = "Present"  # To ensure the user account does not exist, set Ensure to "Absent"
                UserName    =  $UserAdminCredential.UserName
                Password    =  $UserAdminCredential  # This needs to be a credential object
                Description = 'User created by DSC'
                PasswordNeverExpires = $true
                PasswordChangeNotAllowed = $true
                #PsDscRunAsCredential =  $LocalAdminCredential 
                DependsOn   =  $FarmTask
            }            

            $FarmTask = "[User]LocalUserA"
            
            Group AddUserAToLocalAdminGroup {
                GroupName            = 'Administrators'
                Ensure               = 'Present'                
                MembersToInclude     = "user_a"
                Credential           =  $LocalAdminCredential 
                DependsOn            = $FarmTask             
            }
            $FarmTask = "[Group]AddUserAToLocalAdminGroup"
            #>        
        }

        ## JumpBox Settings
        #### if Workstation Aka JumpBox         
        if($env:ComputerName -eq "JumpBox") 
        { 
            Script SetWSMANJumpbox
            {
                SetScript = {
                    try {
                    Set-item wsman:\localhost\Client\TrustedHosts -value "*" -ErrorAction SilentlyContinue 
                    }
                    catch {
                    Write-Verbose "Something went wrong during setting Set-Item WSMAN "
                    }
                }
    
                TestScript = {                                 
                    return $false
                }
                GetScript = { $null }                
            }
    
            $FarmTask = "[Script]SetWSMANJumpbox"  
             
           
                     
            <#
            PackageManagementSource SourceRepository
            {
                Ensure      = "Present"
                Name        = "MyNuget"
                ProviderName= "Nuget"
                SourceLocation   = "https://api.nuget.org/v3/"
                InstallationPolicy ="Trusted"
            }
            
            PackageManagementSource PSGallery
            {
                Ensure          = "Present"
                Name            = "psgallery"
                ProviderName    = "PowerShellGet"
                SourceLocation   = "https://www.powershellgallery.com/api/v2/"
                InstallationPolicy ="Trusted"
            }
            #>

            <# 
            PackageManagement NugetPackage
            {
                Ensure               = "Present"
                Name                 = "JQuery"
                AdditionalParameters = "$env:HomeDrive\nuget"
                RequiredVersion      = "2.0.1"
                DependsOn            = "[PackageManagementSource]SourceRepository"
            }
        
            PackageManagement PSModule
            {
                Ensure               = "Present"
                Name                 = "gistprovider"
                Source               = "PSGallery"
                DependsOn            = "[PackageManagementSource]PSGallery"
            }
            #>

            $packages = $ConfigData.packages           
            
            $packageProviderName = "ChocolateyGet"

            Script DevSetup
            {
                SetScript = {
                    try {
                        
                        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

                        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
                        Install-PackageProvider -Name $using:packageProviderName -ErrorAction SilentlyContinue              
                        Install-PackageProvider "NuGet"  -Force -MinimumVersion 2.8 | Out-Null
                        #-ErrorAction SilentlyContinue # -RequiredVersion 2.8.5.201
                            
                        Import-PackageProvider -Name $using:packageProviderName              
                            
                        $using:packages | ForEach-Object -Process {
                                If(-Not (Get-Package -Name $_ -ProviderName $using:packageProviderName -ErrorAction SilentlyContinue)) 
                                {
                                    Install-Package -Name $_ -ProviderName $using:packageProviderName -Confirm:$false -Force
                                }
                        }
                    }
                    catch {
                        Write-Verbose "Could NOT install packages, will try again in next run"
                    }
                }

                TestScript = {
                    
                        $var = $true
                        
                        try {
                            
                            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

                            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
                            Install-PackageProvider -Name $using:packageProviderName -ErrorAction SilentlyContinue              
                            Install-PackageProvider "NuGet"  -Force -MinimumVersion 2.8 | Out-Null
                            #-ErrorAction SilentlyContinue # -RequiredVersion 2.8.5.201

                            Import-PackageProvider -Name $using:packageProviderName      

                            $using:packages | ForEach-Object -Process {
                                If(-Not (Get-Package -Name $_ -ProviderName $using:packageProviderName -ErrorAction SilentlyContinue)) 
                                {
                                    $var = $false
                                }
                            }
                        }
                        catch { 

                        }

                        return $var         
                    }
                GetScript = { $null }                          
            }

            $FarmTask = "[Script]DevSetup"  
            
        }
        ## END JumpBox Github Settings       

        if($joinDomain)
        {
            # wait domain is available before joinning this computer to domain
            xWaitForADDomain DscForestWait
            {
                DomainName = $DomainName
                DomainUserCredential= $DomainAdminCredential
                RetryCount = $RetryCount
                RetryIntervalSec = $RetryIntervalSec
                DependsOn = $FarmTask  
            }
            $FarmTask = "[xWaitForADDomain]DscForestWait"          
    
            # once domain is available join this computer to domain.
            Computer JoinDomain
            {
                Name       = $env:COMPUTERNAME
                DomainName = $DomainName
                Credential = $DomainAdminCredential 
                DependsOn  = $FarmTask  
            }            
            $FarmTask = "[Computer]JoinDomain"    
            
            # Wait V site Domain Controller so user_a will be available
            $DomainController = ""
            if($ServerSite -eq "V"){ $DomainController = "VD201"; } elseif($ServerSite -eq "C" ) { $DomainController = "CD201";}

            if($DomainController -ne "") {
                WaitForAll BDC
                {
                    NodeName            = $DomainController
                    ResourceName        = "[xADDomainController]BDC"
                    PsDscRunAsCredential = $DomainAdminCredential
                    RetryCount          = $RetryCount
                    RetryIntervalSec    = $RetryIntervalSec  
                    DependsOn           = $FarmTask 
                }
                $FarmTask = "[WaitForAll]BDC"  
            }

            Group AddUserAToLocalAdminGroup {
                GroupName            = 'Administrators'
                Ensure               = 'Present'
                MembersToInclude     = "$($DomainNetbiosName)\user_a"
                Credential           =  $DomainAdminCredential 
                #PsDscRunAsCredential =  $DomainAdminCredential
                DependsOn           = $FarmTask
            }
            $FarmTask = "[Group]AddUserAToLocalAdminGroup"
        }      

        # Move DVD optical drive letter E to Z
        OpticalDiskDriveLetter MoveDiscDrive
        {
            DiskId      = 1
            DriveLetter = 'Z' # This value is ignored if absent
            Ensure      = 'Present'
            DependsOn  = $FarmTask  
        }

        $FarmTask = "[OpticalDiskDriveLetter]MoveDiscDrive"    

        # removes pagefile on Drive and move D drive to T and sets back page file on that drive
        Script DeletePageFile
        {
            SetScript = {
                # change C drive label to "System" from "Windows"
                $drive = Get-WmiObject win32_volume -Filter "DriveLetter = 'C:'" -ErrorAction SilentlyContinue
                $drive.Label = "System"
                $drive.put()
                
                $cpf = Set-WMIInstance -Class Win32_PageFileSetting -Arguments @{ Name = "C:\pagefile.sys"; MaximumSize = 0; } -ErrorAction SilentlyContinue

                #Get-WmiObject win32_pagefilesetting
                $pf = Get-WmiObject -Query "select * from Win32_PageFileSetting where name='D:\\pagefile.sys'" -ErrorAction SilentlyContinue                
                if($pf -ne $null) {$pf.Delete()}  
            }

            TestScript = {                                 
                $CurrentPageFile = Get-WmiObject win32_volume -Filter "DriveLetter = 'T:'" -ErrorAction SilentlyContinue 
                if($CurrentPageFile -eq $null) { return $false } else {return $true }
            }
            GetScript = { $null } 
            DependsOn  = $FarmTask       
        }

        $FarmTask = "[Script]DeletePageFile"    

        xPendingReboot Reboot1
        {
            name = "After deleting PageFile"
            DependsOn  = $FarmTask
        }
        $FarmTask = "[xPendingReboot]Reboot1"    

        # removes pagefile on Drive and move D drive to T and sets back page file on that drive
        Script DDrive
        {
            SetScript = {
                
                $drive = Get-Partition -DriveLetter "D" | Set-Partition -NewDriveLetter "T"  -ErrorAction SilentlyContinue

                $tpf = Set-WMIInstance -Class Win32_PageFileSetting -Arguments @{ Name = "T:\pagefile.sys"; MaximumSize = 0; } -ErrorAction SilentlyContinue

                $pf = Get-WmiObject -Query "select * from Win32_PageFileSetting where name='C:\\pagefile.sys'" -ErrorAction SilentlyContinue                
                if($pf -ne $null) {$pf.Delete()}  

            }

            TestScript = {                                 
                $CurrentPageFile = Get-WmiObject win32_volume -Filter "DriveLetter = 'T:'" -ErrorAction SilentlyContinue 
                if($CurrentPageFile -eq $null) { return $false } else {return $true }
            }
            GetScript = { $null } 
            DependsOn  = $FarmTask                  
            #PsDscRunAsCredential = $DomainAdminCredential

        }
        $FarmTask = "[Script]DDrive"

        # convert DataDisks Json string to array of objects
        $DataDisks = $DataDisks | ConvertFrom-Json        

        
        if($DataDisks.Count -gt 0){
            # loop each Datadisk information and mount to a letter in object
            $count = 2 # start with "2" ad "0" and "1" is for  C  and D that comes from WindowsServer Azure image 

            # if size eq small wait only one data disk
            if($DiskSize -ne "Default") {
                # wait for disk is mounted to vm and available   
                WaitForDisk DataDisk
                {
                    DiskId = $count 
                    RetryIntervalSec = $RetryIntervalSec
                    RetryCount = $RetryCount
                    DependsOn  = $FarmTask
                }
                
                $FarmTask = "[WaitForDisk]DataDisk"               
            }
        }

        $DisksizeGB  = [int64]$DisksizeGB * 1GB
    
        foreach ($datadisk in $DataDisks)
        {
            $letter = $datadisk.letter            
            $label = $datadisk.name           
            
            $drive = Get-WmiObject win32_volume -Filter "Label = '$($label)'" -ErrorAction SilentlyContinue
            #$drive = Get-WmiObject win32_volume -Filter "DriveLetter = '$($letter):'" -ErrorAction SilentlyContinue

            #(Get-Volume -DriveLetter $datadisk.letter -ErrorAction SilentlyContinue) -ge 1
            
            if(!$drive) {
                if($DiskSize -ne "Default") {
                    # once disk number availabe, assign and format drive with all available sizes and assign a leter and label that comes from parameters.
                    <# 
                    if(($DataDisks.Length -1 ) -eq $DataDisks.IndexOf($datadisk))
                    {                    
                        Disk $datadisk.letter
                        {
                            FSLabel = $datadisk.name
                            DiskId = $count 
                            DriveLetter = $datadisk.letter                  
                            DependsOn  = $FarmTask
                        }
                        
                    }                
                    else {
                        Disk $datadisk.letter
                        {
                            FSLabel = $datadisk.name
                            DiskId = $count
                            DriveLetter = $datadisk.letter
                            Size = $DisksizeGB
                            DependsOn  = $FarmTask
                        }
                    }
                    #>

                    Disk $datadisk.letter
                    {
                        FSLabel = $datadisk.name
                        DiskId = $count
                        DriveLetter = $datadisk.letter
                        Size = $DisksizeGB
                        DependsOn  = $FarmTask
                    }

                    $FarmTask = "[Disk]$($datadisk.letter)"

                    $DisksizeGB += 0.01GB
                }
                else{
                    # wait for disk is mounted to vm and available   
                    WaitForDisk $datadisk.name
                    {
                        DiskId = $count
                        RetryIntervalSec = $RetryIntervalSec
                        RetryCount = $RetryCount
                        DependsOn  = $FarmTask
                    }
                    $FarmTask = "[WaitForDisk]$($datadisk.name)"
                    # once disk number availabe, assign and format drive with all available sizes and assign a leter and label that comes from parameters.
                    Disk $datadisk.letter
                    {
                        FSLabel = $datadisk.name
                        DiskId = $count
                        DriveLetter = $datadisk.letter
                        DependsOn  = $FarmTask
                    }
                    $FarmTask = "[Disk]$($datadisk.letter)"
                    $count ++
                }
            }
        }

        ## JumpBox Github Settings
        ## Clone Git Repositories
        if($env:ComputerName -eq "JumpBox" -And ($ConfigData.githubUsername) -And ($ConfigData.githubToken)) {
            
            $Repositories = $ConfigData.GitRepositories
            $githubUsername   = $ConfigData.githubUsername
            $githubToken      = $ConfigData.githubToken
            $githubUrl           = $ConfigData.githubUrl
            

            Script CloneRepositories
            {
                SetScript = {
                    try { 
                        if(-Not (Test-Path -path "C:\github"))
                        {
                            New-Item -Path "c:\" -Name "github" -Itemtype "directory" 
                        }

                        Set-Location -Path "C:\github"

                        $using:Repositories | ForEach-Object -Process { 
                            $url = "https://"
                            $url += "$($using:githubUsername):$($using:githubToken)@"
                            $url += "$($using:githubUrl)" 
                            $url += "/$_"
                            $url += '.git'
                            #github.dxc.com/AdvSol/' https://github.com/MehmetVural/
                            
                            if(-Not (Test-Path -path "c:\github\$_"))
                            {
                                git clone $url -q
                            }
                        }

                        if(Test-Path -path "C:\github\SE.DevOps.DSC\Common")
                        {
                            # Imports Common CI Utilities
                            # Write-Host "Importing Common Module" -ForegroundColor DarkCyan
                            if((Get-Module -Name 'Common')){ Remove-Module -Name 'Common' }
                            Import-Module -Name 'C:\github\SE.DevOps.DSC\Common\Common.psd1' -DisableNameChecking
                            #Get-Repositories  -RepositoryRoot "C:\github" -GithubUsername "$($using:githubUsername)" -GithubToken "$($using:githubToken)" -GithubUrl "$($using:githubUrl)"
                                
                            # Imports Common CI Utilities
                            # Write-Host "Importing Common Module" -ForegroundColor DarkCyan
                            if((Get-Module -Name 'Common')){ Remove-Module -Name 'Common' }
                            Import-Module -Name 'C:\github\SE.DevOps.DSC\Common\Common.psd1' -DisableNameChecking
                            # Install additional packages
                            #& "C:\github\Common\AzurePostConfigurations.ps1"
                            Set-PostConfigurations                            
                        }
                    }
                    catch {
                        Write-Verbose "Can not colone git repositories."
                    }
                }

                TestScript = { 
                    $var = $true

                    $using:Repositories | ForEach-Object -Process { 
                        if(-Not (Test-Path -path "C:\github\$_")) 
                        {
                            $var = $false                             
                        }
                    }

                    return $var
                }
                GetScript = { $null }   
                DependsOn           = $FarmTask   
                    
            }
            $FarmTask = "[Script]CloneRepositories"
        }

        <#
        if(($env:ComputerName -eq "JumpBox") -or ($ServiceName -eq "InternalTest") )
        { 
            $ClientInstallPath  =  $ConfigData.ClientInstallPath
            $InstallOffice      =  $ConfigData.InstallOffice
            $DestinationPath    =  $ConfigData.DestinationPath 
           
            File DirectoryCopy
            {
                Ensure          = "Present" # Ensure the directory is Present on the target node.
                Type            = "Directory" # The default is File.
                Recurse         = $true # Recursively copy all subdirectories.
                SourcePath      = $ClientInstallPath
                DestinationPath = $DestinationPath
                Credential      = $DomainAdminCredential
            }
            $FarmTask  = "[File]DirectoryCopy"
        }
        #>

        ### Service Additional Settings
        if($ServiceName -eq "DNS"){
            ##  START DNS Services
            # Install DNS windows features 
            @("DNS") | ForEach-Object -Process {
                    WindowsFeature "DNS-Feature-$_"
                    {
                        Ensure = "Present"
                        Name = $_                   
                    }
                    
            }
            
            $ZoneName =  $ConfigData.ZoneName
            $ZoneFile =  $ConfigData.ZoneFile
            $DynamicUpdate =  $ConfigData.DynamicUpdate
            $TransferType =  $ConfigData.TransferType
            $PrimaryServerIP = $ConfigData.PrimaryServerIP
            $PrimaryServer = $ConfigData.PrimaryServer
            $SecondaryServerIP = $ConfigData.SecondaryServerIP
            $SecondaryServer = $ConfigData.SecondaryServer

            if($ServerName -eq $PrimaryServer)
            {
                <# 
                    xDnsServerSetting DnsServerProperties
                    {
                        Name = 'DnsServerSetting'
                        ListenAddresses = '10.0.0.4'
                        IsSlave = $true
                        Forwarders = '168.63.129.16','168.63.129.18'
                        RoundRobin = $true
                        LocalNetPriority = $true
                        SecureResponses = $true
                        NoRecursion = $false
                        BindSecondaries = $false
                        StrictFileParsing = $false
                        ScavengingInterval = 168
                        LogLevel = 50393905
                    }
                #>
                # Initiate Primary Zone
                xDnsServerPrimaryZone addPrimaryZone
                {
                    Ensure        = 'Present'
                    Name          = $ZoneName
                    ZoneFile      = $ZoneFile
                    DynamicUpdate = $DynamicUpdate                    
                }
                $FarmTask = "[xDnsServerPrimaryZone]addPrimaryZone"   

                xDnsServerZoneTransfer TransferToAnyServer
                {
                    Name            = $ZoneName
                    Type            = $TransferType
                    SecondaryServer = $SecondaryServerIP
                    
                }
            
            }

            if($ServerName -eq $SecondaryServer)
            {
                ##Wait for Primary Zone
                WaitForAll PrimaryZone
                {
                    ResourceName = '[xDnsServerZoneTransfer]TransferToAnyServer'
                    NodeName = $PrimaryServer
                    RetryIntervalSec = 60
                    RetryCount = 30
                }
                # Initiate Secondary Zone
                xDnsServerSecondaryZone addSecondaryZone
                {
                    Ensure        = 'Present'
                    Name          = $ZoneName
                    MasterServers = $PrimaryServerIP
                    DependsOn = "[WaitForAll]PrimaryZone"
                }
            }
        }        
        elseif ($ServiceName -eq "NPS"){
            ##  START NPS Services
            $WindowsFeatures =  $ConfigData.WindowsFeatures
            $VPNServers =  $ConfigData.VPNServers
                
            if($VPNServers -contains $ServerName) 
            {
                # Install DNS windows features
                $WindowsFeatures | ForEach-Object -Process {
                        WindowsFeature "NPS-Feature-$_"
                        {
                            Ensure = "Present"
                            Name = $_                   
                        }                                       
                }   
            }

        }
        elseif ($ServiceName -eq "Skype"){
            ##  START Skype Installation Services
            
            #$WindowsFeatures =  $ConfigData.WindowsFeatures
            #$VPNServers =  $ConfigData.VPNServers
        }                 
        elseif ($ServiceName -eq "CertificateAuthority"){

           
            $WindowsFeatures =  $ConfigData.WindowsFeatures                
            
            # Install DNS windows features
            $WindowsFeatures | ForEach-Object -Process {
                    WindowsFeature "CA-Feature-$_"
                    {
                        Ensure = "Present"
                        Name = $_
                    } 
                    $DependsOnTask =  "[WindowsFeature]CA-Feature-$_"   
            }

            xDnsRecord CaDnsRecord
            {
                Name        = "ca"
                Target      = $ServerIP
                Zone        = $DomainName
                Type        = "ARecord"
                DnsServer   = $DnsServer
                Ensure      = "Present"
                PsDscRunAsCredential = $DomainAdminCredential
                DependsOn        = $DependsOnTask
            }            


            AdcsCertificationAuthority CertificateAuthority
            {
                IsSingleInstance    = 'Yes'
                Ensure              = 'Present'
                Credential          =  $DomainAdminCredential
                CAType              = 'StandaloneRootCA'  #'EnterpriseRootCA'
                CryptoProviderName  = "ECDSA_P256#Microsoft Software Key Storage Provider"                
                KeyLength           = 256
                HashAlgorithmName   = "SHA256"
                DependsOn           = $DependsOnTask
            }
            $DependsOnTask =  "[AdcsCertificationAuthority]CertificateAuthority"   

            <# AdcsEnrollmentPolicyWebService EnrollmentPolicyWebService
            {
                AuthenticationType = 'Certificate'
                SslCertThumbprint  = 'f0262dcf287f3e250d1760508c4ca87946006e1e'
                Credential         = $DomainAdminCredential
                KeyBasedRenewal    = $true
                Ensure             = 'Present'                
                DependsOn        = $DependsOnTask
            }

            $DependsOnTask =  "[AdcsEnrollmentPolicyWebService]EnrollmentPolicyWebService"   
            #>

            AdcsWebEnrollment WebEnrollment
            {
                Ensure           = 'Present'
                IsSingleInstance = 'Yes'
                Credential       = $DomainAdminCredential                
                DependsOn        = $DependsOnTask
            }
            $DependsOnTask =  "[AdcsWebEnrollment]WebEnrollment"   
            #"Installs the Web Enrollment website. URL is:http://<servername>.domain.com/certsrv"
        }
        elseif ($ServiceName -eq "SharedSQL") 
        {
            ##  START SHARED SQL INSTALLATIONS
            
            #$ConfigData | ConvertTo-Json |  Out-File -FilePath C:\ConfigData.txt
            #$ConfigData | Out-File -FilePath C:\json.txt

            $SqlAdministratorCredential = $InstallCredential
            $SqlServiceCredential       = $InstallCredential   
            $SqlAgentServiceCredential  = $InstallCredential
            
            #$ServerSite | Out-File -FilePath C:\ServerSite.txt

            $Nodes         = $ConfigData.Nodes  # $ConfigData[$ServerSite] not site specific Availibility group any more, one giant AG replicas
            $NonNodeData   = $ConfigData.NonNodeData
            $Settings      = $ConfigData.DatabaseSettings

            #$Nodes | ConvertTo-Json | Out-File -FilePath C:\Nodes.txt

            $Node = $Nodes.Where{$_.Name -eq $ServerName} 
            
            #$Node | ConvertTo-Json | Out-File -FilePath C:\Node.txt

            $ClusterIPAddress = $NonNodeData.ClusterIPAddress
            $ClusterName      = $NonNodeData.ClusterName
        
            $ClusterNodes = @();

            $Nodes.foreach({
                $ClusterNodes += $_.Name
            });

            # xCredSSP CredSSPServer
            # {
            #     Ensure = 'Present'
            #     Role = 'Server'
            # }

            # xCredSSP CredSSPClient
            # {
            #     Ensure = 'Present'
            #     Role = 'Client'
            #     DelegateComputers = "*.$($DomainName)"
            # }
                            
            @(
                "Failover-clustering",            
                "RSAT-Clustering-PowerShell",
                "RSAT-Clustering-CmdInterface",
                "RSAT-Clustering-Mgmt"
            ) | ForEach-Object -Process {
                WindowsFeature "SQL-Feature-$_"
                {
                    Ensure      = "Present"
                    Name        = $_
                    DependsOn   = $FarmTask 
                }
                $FarmTask = "[WindowsFeature]SQL-Feature-$_"
            }          

            if ( $Node.Role -eq 'FirstServer' )      
            {                 
                WaitForAll ClusterFeature
                {
                    ResourceName            = '[WindowsFeature]SQL-Feature-RSAT-Clustering-CmdInterface'
                    NodeName                = $Nodes.Name
                    RetryCount              = $RetryCount
                    RetryIntervalSec        = $RetryIntervalSec
                    PsDscRunAsCredential    = $InstallCredential
                    DependsOn               = $FarmTask 
                }
                $FarmTask = "[WaitForAll]ClusterFeature"
                
                Script CreateCluster
                {
                    SetScript = {
                            $ClusterService = Get-Service "ClusSvc"
                        
                        If($ClusterService) 
                            {
                                New-Cluster $using:ClusterName -Node $using:ClusterNodes -StaticAddress $using:ClusterIPAddress -NoStorage -AdministrativeAccessPoint Dns
                            }
                            #Get-Cluster -Name 'mc21'  | Add-ClusterNode -Name "VS222"
                            #Get-Cluster -Name MyCl1 | Add-ClusterNode -Name node3

                    }
                    TestScript = {  
                                    $ClusterService = Get-Service "ClusSvc"

                                    If($ClusterService) 
                                    {
                                        if($ClusterService.StartType -ne "Disabled")
                                        {
                                            if(Get-Cluster) {
                                            return $true
                                            }
                                            else{return $true}
                                        }
                                        else
                                        {
                                            return $false
                                        }                                 
                                    }
                                    else {return $true}
                    
                    }

                    GetScript = { $null }                    
                    PsDscRunAsCredential  =  $InstallCredential     
                    DependsOn   = $FarmTask 
                }
                $FarmTask = "[Script]CreateCluster"
            }
        }
        elseif ($ServiceName -eq "SharedSQLFull") 
        {
            ##  START SHARED SQL INSTALLATIONS
            
            #$ConfigData | ConvertTo-Json |  Out-File -FilePath C:\ConfigData.txt
            #$ConfigData | Out-File -FilePath C:\json.txt

            $SqlAdministratorCredential = $DomainAdminCredential
            $SqlServiceCredential       = $DomainAdminCredential   
            $SqlAgentServiceCredential  = $DomainAdminCredential
            
            #$ServerSite | Out-File -FilePath C:\ServerSite.txt

            $Nodes         = $ConfigData.Nodes  # $ConfigData[$ServerSite] not site specific Availibility group any more, one giant AG replicas
            $NonNodeData   = $ConfigData.NonNodeData
            $Settings      = $ConfigData.DatabaseSettings

            #$Nodes | ConvertTo-Json | Out-File -FilePath C:\Nodes.txt

            $Node = $Nodes.Where{$_.Name -eq $ServerName} 
            
            #$Node | ConvertTo-Json | Out-File -FilePath C:\Node.txt

            $ClusterIPAddress = $NonNodeData.ClusterIPAddress
            $ClusterName      = $NonNodeData.ClusterName
        
            $ClusterNodes = @();

            $Nodes.foreach({
                $ClusterNodes += $_.Name
            });

            # xCredSSP CredSSPServer
            # {
            #     Ensure = 'Present'
            #     Role = 'Server'
            # }

            # xCredSSP CredSSPClient
            # {
            #     Ensure = 'Present'
            #     Role = 'Client'
            #     DelegateComputers = "*.$($DomainName)"
            # }
                
            @(
                "Failover-clustering",            
                "RSAT-Clustering-PowerShell",
                "RSAT-Clustering-CmdInterface",
                "RSAT-Clustering-Mgmt"
            ) | ForEach-Object -Process {
                WindowsFeature "SQLF-Feature-$_"
                {
                    Ensure      = "Present"
                    Name        = $_
                    DependsOn   = $FarmTask 
                }
                $FarmTask = "[WindowsFeature]SQLF-Feature-$_"
            }

            if ( $Node.Role -eq 'FirstServer' )      
            {                 
                WaitForAll ClusterFeature
                {
                    ResourceName            = '[WindowsFeature]SQLF-Feature-RSAT-Clustering-CmdInterface'
                    NodeName                = $Nodes.Name
                    RetryCount              = $RetryCount
                    RetryIntervalSec        = $RetryIntervalSec
                    PsDscRunAsCredential    = $DomainAdminCredential
                    DependsOn               = $FarmTask 
                }
                $FarmTask = "[WaitForAll]ClusterFeature"
                
                Script CreateCluster
                {
                    SetScript = {
                            $ClusterService = Get-Service "ClusSvc"
                        
                        If($ClusterService) 
                            {
                                New-Cluster $using:ClusterName -Node $using:ClusterNodes -StaticAddress $using:ClusterIPAddress -NoStorage -AdministrativeAccessPoint Dns
                            }
                            #Get-Cluster -Name 'mc21'  | Add-ClusterNode -Name "VS222"
                            #Get-Cluster -Name MyCl1 | Add-ClusterNode -Name node3

                    }
                    TestScript = {  
                                    $ClusterService = Get-Service "ClusSvc"

                                    If($ClusterService) 
                                    {
                                        if($ClusterService.StartType -ne "Disabled")
                                        {
                                            if(Get-Cluster) {
                                            return $true
                                            }
                                            else{return $true}
                                        }
                                        else
                                        {
                                            return $false
                                        }                                 
                                    }
                                    else {return $true}
                    
                    }

                    GetScript = { $null }                    
                    PsDscRunAsCredential  =  $DomainAdminCredential     
                    DependsOn   = $FarmTask 
                }
                $FarmTask = "[Script]CreateCluster"               
                
            }

            # Depreciated copy to local from extracted files.
            <#

            MountImage ISO
            {
                ImagePath   =  $Settings.SQLInstalISO
                DriveLetter = 'S'
                Ensure = "Present"
                PsDscRunAsCredential = $InstallCredential  
                DependsOn   = $FarmTask 
            }
            $FarmTask = "[MountImage]ISO"

            WaitForVolume WaitForISO
            {
                DriveLetter      = 'S'
                RetryCount = $RetryCount
                RetryIntervalSec = $RetryIntervalSec
                DependsOn   = $FarmTask 
            }
            $FarmTask = "[WaitForVolume]WaitForISO"
            
            #>
            
            # copy SQL binarias to local drive           

            # File DirectoryCopy
            # {
            #     Ensure = "Present" # Ensure the directory is Present on the target node.
            #     Type = "Directory" # The default is File.
            #     Recurse = $true # Recursively copy all subdirectories.
            #     SourcePath = $Settings.SQLInstallSource
            #     DestinationPath = $Settings.SQLInstallDestination            
            #     Credential = $DomainAdminCredential            
            # }

            Registry DisableIPv6
            {
                Key       = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
                ValueName = 'DisabledComponents'
                ValueData = 'ff'
                ValueType = 'Dword'
                Hex       = $true
                Ensure    = 'Present'
            }
                
            Registry DisableLoopBackCheck 
                    {
                    Ensure = "Present"
                    Key = "HKLM:\System\CurrentControlSet\Control\Lsa"
                    ValueName = "DisableLoopbackCheck"
                    ValueData = "1"
                    ValueType = "Dword"
            }

            # Firewall is disabled    
            # # endregion Install SQL Server
            # Firewall SQLEngineFirewallRule
            # {
            #     Name         = 'SQLDatabaseEngine'
            #     DisplayName  = 'SQL Server Database Engine'
            #     Group        = 'SQL Server Rules'
            #     Ensure       = 'Present'
            #     Action       = 'Allow'
            #     Enabled      = 'True'
            #     Profile      = ('Domain', 'Private')
            #     Direction    = 'Inbound'
            #     LocalPort    = ('1433', '1434')
            #     Protocol     = 'TCP'
            #     Description  = 'SQL Database engine exception'
            #     DependsOn   = $FarmTask 
            # }
            # $FarmTask = "[Firewall]SQLEngineFirewallRule"  
            
            
            # # endregion Install SQL Server
            # Firewall SQLEngineFailoverCluster
            # {
            #     Name         = 'SQLFailover'
            #     DisplayName  = 'SQL Failover Sync'
            #     Group        = "SQL Server Rules"
            #     Ensure       = 'Present'
            #     Action       = 'Allow'
            #     Enabled      = 'True'
            #     Profile      = ('Domain', 'Private')
            #     Direction    = 'Inbound'
            #     LocalPort    = ('5022', '5022')
            #     Protocol     = 'TCP'
            #     Description  = 'SQL Failover Port'
            #     DependsOn    = $FarmTask 
            # }
            # $FarmTask = "[Firewall]SQLEngineFailoverCluster"  
            
            
            WaitForAll Cluster
            {
                NodeName                = $Nodes.Where{$_.Role -eq "FirstServer"}.Name
                ResourceName            = "[Script]CreateCluster"
                PsDscRunAsCredential    = $SqlAdministratorCredential
                RetryCount              = $RetryCount
                RetryIntervalSec        = $RetryIntervalSec
                DependsOn               = $FarmTask 
            }
            $FarmTask = "[WaitForAll]Cluster"

            if ( $Node.SqlDnsPrefix -ne '' -and  $Node.DnsServer -ne '')
            {
                $SqlDnsPrefix       = $Node.SqlDnsPrefix
                $DnsServer          = $Node.DnsServer

                xDnsRecord SqlDnsPrefix
                {
                    Name        = $SqlDnsPrefix
                    Target      = $ServerIP
                    Zone        = $DomainName
                    Type        = "ARecord"
                    DnsServer   = $DnsServer
                    Ensure      = "Present"
                    PsDscRunAsCredential = $DomainAdminCredential
                    DependsOn               = $FarmTask 
                }
                $FarmTask = "[xDnsRecord]SqlDnsPrefix"  
            } 
            
            WaitForAll FileShare
            {
                NodeName            = $Settings.ShareServer
                ResourceName        = "[xSmbShare]FileShare"
                PsDscRunAsCredential = $DomainAdminCredential
                RetryCount          = $RetryCount
                RetryIntervalSec    = $RetryIntervalSec  
                DependsOn           = $FarmTask 
            }
            $FarmTask = "[WaitForAll]FileShare"

            #region Install SQL Server
            SqlSetup InstallDefaultInstance
            {
                InstanceName         = $Settings.InstanceName 
                #Features             = 'SQLENGINE,AS'
                Features             = 'SQLENGINE,FULLTEXT,AS,RS'
                #ProductKey           = '' 
                SQLCollation         = 'SQL_Latin1_General_CP1_CI_AS'
                SQLSvcAccount        = $SqlServiceCredential
                AgtSvcAccount        = $SqlAgentServiceCredential             
                AgtSvcStartupType    = "Automatic"
                SqlSvcStartupType    = "Automatic"
                SQLSysAdminAccounts  = $SqlAdministratorCredential.UserName
                InstallSharedDir     = 'C:\Program Files\Microsoft SQL Server'
                InstallSharedWOWDir  = 'C:\Program Files (x86)\Microsoft SQL Server'
                InstanceDir          = 'C:\Program Files\Microsoft SQL Server'
                InstallSQLDataDir    = 'E:\Data'
                SQLUserDBDir         = 'E:\Data'
                SQLUserDBLogDir      = 'F:\Logs'
                SQLTempDBDir         = 'G:\Data'
                SQLTempDBLogDir      = 'G:\Logs'
                SQLBackupDir         = 'H:\Backup'              
                SourcePath           =  $Settings.SQLInstallSource #SQLInstallDestination  Now installing dorectly from UNC Share Path
                UpdateEnabled        = 'False'
                ForceReboot          = $true 
                ASServerMode         = 'TABULAR'
                ASConfigDir          = 'E:\MSOLAP\Config'
                ASDataDir            = 'E:\MSOLAP\Data'
                ASLogDir             = 'F:\MSOLAP\Log'
                ASBackupDir          = 'H:\MSOLAP\Backup'
                ASTempDir            = 'G:\MSOLAP\Data'
                AsSvcStartupType     = "Automatic"
                FTSvcAccount         =  $SqlServiceCredential
                ASSvcAccount         =  $SqlServiceCredential
                RSSvcAccount         =  $SqlServiceCredential
                RsSvcStartupType     =  "Automatic"
                BrowserSvcStartupType = "Automatic"
                PsDscRunAsCredential = $DomainAdminCredential                   
                DependsOn            = $FarmTask 
            }
            $FarmTask = "[SqlSetup]InstallDefaultInstance"  
            
            
            SqlServerLogin DomainAdminLogin
            {
                Name                    = "$($DomainNetbiosName)\Domain Admins"
                LoginType               = 'WindowsGroup'
                ServerName              = $ServerName
                InstanceName            = 'MSSQLSERVER'                 
                PsDscRunAsCredential    = $SqlAdministratorCredential
                DependsOn               = $FarmTask 
            }
            $FarmTask = "[SqlServerLogin]DomainAdminLogin"  
           

            SqlRS DefaultConfiguration
            {
                InstanceName         = $Settings.InstanceName 
                DatabaseServerName   = $Node.Name
                DatabaseInstanceName = $Settings.InstanceName 
                PsDscRunAsCredential = $DomainAdminCredential 
                DependsOn            = $FarmTask 
            }
            $FarmTask = "[SqlRS]DefaultConfiguration"  
        
            # Adding the required service account to allow the cluster to log into SQL
            SqlServerLogin AddNTServiceClusSvc
            {
                Ensure               = 'Present'
                Name                 = 'NT SERVICE\ClusSvc'
                LoginType            = 'WindowsUser'
                ServerName           = $Node.Name
                InstanceName         = $Settings.InstanceName 
                PsDscRunAsCredential = $SqlAdministratorCredential
                DependsOn            = $FarmTask 
            }
            $FarmTask = "[SqlServerLogin]AddNTServiceClusSvc"  

            # Add the required permissions to the cluster service login
            SqlServerPermission AddNTServiceClusSvcPermissions
            {
                Ensure               = 'Present'
                ServerName           = $Node.Name
                InstanceName         = $Settings.InstanceName 
                Principal            = 'NT SERVICE\ClusSvc'
                Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState'
                PsDscRunAsCredential = $SqlAdministratorCredential
                DependsOn            = $FarmTask 
            }
            $FarmTask = "[SqlServerPermission]AddNTServiceClusSvcPermissions"  

            SqlAlwaysOnService EnableHADR
            {
                Ensure               = 'Present'
                InstanceName         = $Settings.InstanceName 
                ServerName           = $Node.Name
                PsDscRunAsCredential = $SqlAdministratorCredential
                DependsOn            = $FarmTask 
            }
            $FarmTask = "[SqlAlwaysOnService]EnableHADR"  

            # Create a DatabaseMirroring endpoint
            SqlServerEndpoint HADREndpoint
            {                
                EndPointName          = 'HADR'
                Ensure                = 'Present'
                Port                  = 5022
                ServerName            = $Node.Name
                InstanceName          = $Settings.InstanceName 
                PsDscRunAsCredential  = $SqlAdministratorCredential
                DependsOn             = $FarmTask 
            }
            $FarmTask = "[SqlServerEndpoint]HADREndpoint"           

            # Add SQL Service accounts to permissions for endpoint for Endpoints for HADR
            # required if used a service accounts 
            <# 
            SqlServerEndpointPermission EndpointPermission
            {
                Ensure               = 'Present'
                InstanceName         = $Settings.InstanceName            
                ServerName           = $Node.NodeName           
                Name                 = 'HADR'
                Principal            = $Accounts["SqlServiceCredential"].UserName
                DependsOn = @(
                            "[SqlServerEndpoint]HADREndpoint"
                )
            }
            #>

            <#
            # install Microsoft SQL Server Management Studio
            Package SQLStudio
            {
                    Ensure = "Present"   
                    Name = "Microsoft SQL Server Management Studio"
                    Path = $Settings.SQLManagementStudio2016Path          
                    ProductId = $Settings.SQLManagementStudio2016ProductId
                    Arguments = "/install /passive /norestart"
                    PsDscRunAsCredential = $SqlAdministratorCredential
                    #LogPath = [string] 
                    #DependsOn = "[SqlSetup]InstallDefaultInstance"            
            }
            #>

            if ( $Node.Role -eq 'FirstServer' )
            {               
                SqlDatabase CreateDatabase1
                {
                    Ensure       = 'Present'
                    Name         = "TestDB1"
                    ServerName   = $Node.Name
                    InstanceName = $Settings.InstanceName
                    PsDscRunAsCredential = $SqlAdministratorCredential
                    DependsOn    = $FarmTask 
                }
                $FarmTask = "[SqlDatabase]CreateDatabase1"  

                SqlDatabase CreateDatabase2
                {
                    Ensure               = 'Present'
                    Name                 = "TestDB2"
                    ServerName           =  $Node.Name
                    InstanceName         = $Settings.InstanceName
                    PsDscRunAsCredential = $SqlAdministratorCredential
                    DependsOn            = $FarmTask 
                }
                $FarmTask = "[SqlDatabase]CreateDatabase2"  

                SqlAG AddTestAG
                {
                    Ensure                          = 'Present'
                    Name                            = 'TestAG'
                    InstanceName                    = $Settings.InstanceName
                    ServerName                      = $Node.Name                
                    AvailabilityMode                = "SynchronousCommit"
                    BackupPriority                  = 50
                    ConnectionModeInPrimaryRole     = "AllowAllConnections"
                    ConnectionModeInSecondaryRole   = "AllowAllConnections"
                    FailoverMode                    = "Automatic"
                    EndpointHostName                = $Node.Name                   
                    PsDscRunAsCredential            = $SqlAdministratorCredential
                    DependsOn                       = $FarmTask 
                } 
                $FarmTask = "[SqlAG]AddTestAG"

                $Nodes.Where{$_.Role -eq "Secondary"}.Name | ForEach-Object -Process { 
                    # Add the availability group replica to the availability group
                    
                    SqlAGReplica "AddReplica-$_"
                    {
                        Ensure                        = 'Present'
                        Name                          = $_
                        AvailabilityGroupName         = $Settings.AvailabilityGroupName 
                        ServerName                    = $_
                        InstanceName                  = $Settings.InstanceName 
                        ProcessOnlyOnActiveNode       = $false
                        PrimaryReplicaServerName      = $Nodes.Where{$_.Role -eq "FirstServer"}.Name
                        PrimaryReplicaInstanceName    = $Settings.InstanceName                    
                        AvailabilityMode              = "AsynchronousCommit" # SynchronousCommit (SynchronousCommit only allows 3, rest should be AsynchronousCommit)
                        BackupPriority                = 50
                        ConnectionModeInPrimaryRole   = "AllowAllConnections"
                        ConnectionModeInSecondaryRole = "AllowAllConnections"
                        FailoverMode                  = "Manual"  #Automatic (Automatic is only allowed in SynchronousCommit, not in AsynchronousCommit)
                        EndpointHostName              = $_
                        PsDscRunAsCredential          = $SqlAdministratorCredential 
                        DependsOn                     = "[SqlAG]AddTestAG"                      
                    } 
                    $FarmTask = "[SqlAGReplica]AddReplica-$_"
                }

            }

            # if ( $Node.Role -eq 'Secondary' ) 
            # {
            #     #Secondary
                
            #     SqlWaitForAG WaitForAG
            #     {
            #         Name                = 'TestAG'
            #         RetryCount          = $RetryCount
            #         RetryIntervalSec    = $RetryIntervalSec
            #         DependsOn           = $FarmTask 
            #     } 
            #     $FarmTask = "[SqlWaitForAG]WaitForAG"  

            #     # Add the availability group replica to the availability group
            #     SqlAGReplica AddReplica
            #     {
            #         Ensure                        = 'Present'
            #         Name                          = $Node.Name
            #         AvailabilityGroupName         = $Settings.AvailabilityGroupName 
            #         ServerName                    = $Node.Name
            #         InstanceName                  = $Settings.InstanceName 
            #         ProcessOnlyOnActiveNode       = $false
            #         PrimaryReplicaServerName      = $Nodes.Where{$_.Role -eq "FirstServer"}.Name
            #         PrimaryReplicaInstanceName    = $Settings.InstanceName                    
            #         AvailabilityMode              = "AsynchronousCommit" # SynchronousCommit (SynchronousCommit only allows 3, rest should be AsynchronousCommit)
            #         BackupPriority                = 50
            #         ConnectionModeInPrimaryRole   = "AllowAllConnections"
            #         ConnectionModeInSecondaryRole = "AllowAllConnections"
            #         FailoverMode                  = "Manual"  #Automatic (Automatic is only allowed in SynchronousCommit, not in AsynchronousCommit)
            #         EndpointHostName              = $Node.Name                    
            #         PsDscRunAsCredential          = $SqlAdministratorCredential
            #         DependsOn                     = $FarmTask 
            #     } 
            #     $FarmTask = "[SqlAGReplica]AddReplica"
            # }

            if ( $Node.Role -eq 'FirstServer' )
            {               
                # WaitForAll Replica
                # {
                #     ResourceName                = '[SqlAGReplica]AddReplica'
                #     NodeName                    = $Nodes.Where{$_.Role -eq "Secondary"}.Name
                #     RetryCount                  = $RetryCount
                #     RetryIntervalSec            = $RetryIntervalSec
                #     PsDscRunAsCredential        = $SqlAdministratorCredential
                #     DependsOn                   = $FarmTask 
                # }
                # $FarmTask = "[WaitForAll]Replica" 
                
                WaitForAll SQLAGBackup
                {
                    NodeName                = $Settings.ShareServer
                    ResourceName            = "[xSmbShare]SQLAGBackup"
                    PsDscRunAsCredential    = $DomainAdminCredential
                    RetryCount              = $RetryCount
                    RetryIntervalSec        = $RetryIntervalSec
                    DependsOn                     = "[SqlAG]AddTestAG"  
                    #DependsOn               = $FarmTask
                }
                $FarmTask = "[WaitForAll]SQLAGBackup"

                SqlAGDatabase TestAGDatabaseMemberships
                {
                    Ensure                      = 'Present'
                    AvailabilityGroupName       = $Settings.AvailabilityGroupName
                    BackupPath                  = $Settings.SQLAGBackup
                    DatabaseName                = 'TestDB*'
                    InstanceName                = $Settings.InstanceName
                    ServerName                  = $Node.Name
                    #ProcessOnlyOnActiveNode = $true
                    PsDscRunAsCredential        = $SqlAdministratorCredential
                    DependsOn                   = $FarmTask
                }    
                $FarmTask = "[SqlAGDatabase]TestAGDatabaseMemberships"
            }
        }
        elseif ($ServiceName -eq "SCOMFull") {
  
            # Convert Json string to Hashtable
            $Nodes       = $ConfigData[$ServerSite]
            $Config      = $ConfigData.Config

            $Node = $Nodes.Nodes.Where{$_.Name -eq $ServerName} 

            xCredSSP CredSSPServer
            {
                Ensure  = 'Present'
                Role    = 'Server'
            }

            xCredSSP CredSSPClient
            {
                Ensure            = 'Present'
                Role              = 'Client'
                DelegateComputers = "*.$($DomainName)"
            }

            @(
                "Web-WebServer",
                "Web-Request-Monitor",
                "Web-Windows-Auth",
                "Web-Asp-Net",
                "Web-Asp-Net45",
                "NET-WCF-HTTP-Activation45",
                "Web-Mgmt-Console",
                "Web-Metabase"
            ) | ForEach-Object -Process {
                WindowsFeature "SCOMF-Feature-$_"
                {
                    Ensure = "Present"
                    Name = $_
                }
                $FarmTask = "[WindowsFeature]SCOMF-Feature-$_"
            }

            WaitForAll FileShare
            {
                NodeName                = $Config.ShareServer
                ResourceName            = "[xSmbShare]FileShare"
                PsDscRunAsCredential    = $DomainAdminCredential
                RetryCount              = $RetryCount
                RetryIntervalSec        = $RetryIntervalSec               
                DependsOn               = $FarmTask 
            }
            $FarmTask = "[WaitForAll]FileShare" 

            # copy binarias to local drive
            File DirectoryCopy
            {
                Ensure          = "Present" # Ensure the directory is Present on the target node.
                Type            = "Directory" # The default is File.
                Recurse         = $true # Recursively copy all subdirectories.
                SourcePath      = $Config.SCOMInstallSource
                DestinationPath = $Config.SCOMInstallDestination 
                MatchSource     = $true # Matches source to destination
                Credential      = $DomainAdminCredential
                DependsOn      = $FarmTask 
            }
            $FarmTask = "[File]DirectoryCopy"

            # Prerequisties for SCOM report viewing
            Package SQLServer2012SystemCLRTypes
            {
                Ensure      = "Present"
                Name        = "Microsoft System CLR Types for SQL Server 2014"
                ProductId   = $Config.SysClrTypesProductID
                Path        = "$($Config.SCOMInstallDestination)$($Config.SQLSysClrTypesSource)"
                Arguments   = "ALLUSERS=2"
                PsDscRunAsCredential = $DomainAdminCredential
                DependsOn      = $FarmTask 
            }
            $FarmTask = "[Package]SQLServer2012SystemCLRTypes"

            Package ReportViewer2012Redistributable
            {
                Ensure      = "Present"
                Name        = "Microsoft Report Viewer 2015 Runtime"
                ProductID   = $Config.ReportViewerProductID
                Path        = "$($Config.SCOMInstallDestination)$($Config.ReportViewerSource)" 
                Arguments   = "ALLUSERS=2"
                PsDscRunAsCredential = $DomainAdminCredential
                DependsOn      = $FarmTask 
            }
            $FarmTask = "[Package]ReportViewer2012Redistributable"

            # Add service accounts to admins on Management Servers        
            # Group "Administrators"
            # {
            #    GroupName = "Administrators"
            #    MembersToInclude = @(
            #    Node.SystemCenter2012OperationsManagerActionAccount.UserName,
            #    $Node.SystemCenter2012OperationsManagerDASAccount.UserName
            # )     

            WaitForAll SQLServer
            {
                NodeName                = $Nodes.NonNodeData.SqlServerPrimary 
                ResourceName            = "[SqlAlwaysOnService]EnableHADR"
                PsDscRunAsCredential    = $DomainAdminCredential
                RetryCount              = $RetryCount
                RetryIntervalSec        = $RetryIntervalSec
                DependsOn               = $FarmTask 
            }
            $FarmTask = "[WaitForAll]SQLServer"

            $OperationsManagerDBName = $Nodes.NonNodeData.OperationsManagerDBName
            $OperationsManagerDWDBName = $Nodes.NonNodeData.OperationsManagerDWDBName

            if (  $Node.Role -eq 'Primary' )
            {
                # Install first Management Server
                xSCOMManagementServerSetup OMMS
                { 
                    Ensure                  = "Present"
                    SourcePath              = "$($Config.SCOMInstallDestination)$($Config.SCOMSourcePath)"                
                    SourceFolder            = ""
                    SetupCredential         = $DomainAdminCredential
                    #ProductKey             = ""      
                    ManagementGroupName     = $Nodes.NonNodeData.ManagementGroupName
                    FirstManagementServer   = $true
                    ActionAccount           = $DomainAdminCredential
                    DASAccount              = $DomainAdminCredential
                    DataReader              = $DomainAdminCredential
                    DataWriter              = $DomainAdminCredential
                    SqlServerInstance       = $Nodes.NonNodeData.SqlServerInstance
                    DatabaseName            = $OperationsManagerDBName
                    #DatabaseSize           = 100
                    DwSqlServerInstance     = $Nodes.NonNodeData.DwSqlServerInstance
                    DwDatabaseName          = $OperationsManagerDWDBName
                    #DwDatabaseSize         = $Node.DwDatabaseSize
                    PsDscRunAsCredential    = $DomainAdminCredential               
                    DependsOn               = $FarmTask 
                }
                $FarmTask   = "[xSCOMManagementServerSetup]OMMS"

            }

            if ( $Node.Role -eq 'Secondary' )
            {
                WaitForAll OMMS
                {
                    NodeName                = $Nodes.Nodes.Where{$_.Role -eq "Primary"}.Name
                    ResourceName            = "[xSCOMManagementServerSetup]OMMS"
                    PsDscRunAsCredential    = $DomainAdminCredential
                    RetryCount              = $RetryCount
                    RetryIntervalSec        = $RetryIntervalSec
                    DependsOn               = $FarmTask 
                }
                $FarmTask = "[WaitForAll]OMMS"

                # Install additional Management Servers
                xSCOMManagementServerSetup OMMS
                {
                    Ensure                  = "Present"
                    SourcePath              = "$($Config.SCOMInstallDestination)$($Config.SCOMSourcePath)" 
                    SourceFolder            = ""
                    SetupCredential         = $DomainAdminCredential
                    ManagementGroupName     =  $Nodes.NonNodeData.ManagementGroupName
                    FirstManagementServer   = $false
                    ActionAccount           = $DomainAdminCredential
                    DASAccount              = $DomainAdminCredential
                    DataReader              = $DomainAdminCredential
                    DataWriter              = $DomainAdminCredential
                    SqlServerInstance       = $Nodes.NonNodeData.SqlServerInstance
                    DwSqlServerInstance     = $Nodes.NonNodeData.DwSqlServerInstance
                    DependsOn               = $FarmTask 
                }
                $FarmTask = "[xSCOMManagementServerSetup]OMMS"                
            }

            xSCOMConsoleSetup OMC
            {
                Ensure                  = "Present"
                SourcePath              = "$($Config.SCOMInstallDestination)$($Config.SCOMSourcePath)" 
                SourceFolder            = ""
                SetupCredential         = $DomainAdminCredential
                PsDscRunAsCredential    = $DomainAdminCredential
                DependsOn               = $FarmTask 
            }
            $FarmTask = "[xSCOMConsoleSetup]OMC"  
            

            #xSCOMReportingServerSetup OMRS
            #{            
            #    Ensure = "Present"
            #    SourcePath = $Config.SCOMSourcePath
            #    SourceFolder = ""
            #    SetupCredential = $DomainAdminCredential
            #    ManagementServer = $Node.Name 
            #    SRSInstance = $Config.SRSInstance
            #    DataReader = $DomainAdminCredential
            #    PsDscRunAsCredential = $DomainAdminCredential
            #    DependsOn               = $FarmTask 
            #}
            #$FarmTask = "[xSCOMReportingServerSetup]OMRS"  
            

            xSCOMWebConsoleServerSetup OMWC
            {                
                Ensure                  = "Present"
                SourcePath              = "$($Config.SCOMInstallDestination)$($Config.SCOMSourcePath)"
                SourceFolder            = ""
                SetupCredential         = $DomainAdminCredential
                ManagementServer        = $Node.Name
                PsDscRunAsCredential    = $DomainAdminCredential
                DependsOn               = $FarmTask 
            }
            $FarmTask = "[xSCOMWebConsoleServerSetup]OMWC"  
            

            if (  $Node.Role -eq 'Primary' )
            {
                $DnsPrefix       = $Nodes.NonNodeData.DnsPrefix
                $DnsServer       = $Nodes.NonNodeData.DnsServer
                $SqlServerAG     = $Nodes.NonNodeData.SqlServerAG

                xDnsRecord webScomDns
                {
                    Name        = $DnsPrefix
                    Target      = $ServerIP
                    Zone        = $DomainName
                    Type        = "ARecord"
                    DnsServer   = $DnsServer
                    Ensure      = "Present"
                    PsDscRunAsCredential = $DomainAdminCredential
                    DependsOn    = $FarmTask 
                }
                $FarmTask = "[xDnsRecord]webScomDns"
                
                SqlAG AddSCOMAG
                {
                    Ensure                          = 'Present'
                    Name                            = $SqlServerAG
                    InstanceName                    = $Config.InstanceName 
                    ServerName                      = $Nodes.NonNodeData.SqlServerPrimary                
                    AvailabilityMode                = "SynchronousCommit"
                    BackupPriority                  = 50
                    ConnectionModeInPrimaryRole     = "AllowAllConnections"
                    ConnectionModeInSecondaryRole   = "AllowAllConnections"
                    FailoverMode                    = "Automatic"
                    EndpointHostName                = $Nodes.NonNodeData.SqlServerPrimary                 
                    PsDscRunAsCredential            = $DomainAdminCredential
                    DependsOn                       = $FarmTask 
                }
                $FarmTask = "[SqlAG]AddSCOMAG"

                SqlAGReplica AddReplicaSCOMSecondary
                {
                    Ensure                        = 'Present'
                    Name                          = $Nodes.NonNodeData.SqlServerSecondary
                    AvailabilityGroupName         = $SqlServerAG
                    ServerName                    = $Nodes.NonNodeData.SqlServerSecondary
                    InstanceName                  = $Config.InstanceName 
                    ProcessOnlyOnActiveNode       = $false
                    PrimaryReplicaServerName      = $Nodes.NonNodeData.SqlServerPrimary
                    PrimaryReplicaInstanceName    = $Config.InstanceName 
                        
                    AvailabilityMode              = "SynchronousCommit" # SynchronousCommit (SynchronousCommit only allows 3, rest should be AsynchronousCommit)
                    BackupPriority                = 50
                    ConnectionModeInPrimaryRole   = "AllowAllConnections"
                    ConnectionModeInSecondaryRole = "AllowAllConnections"
                    FailoverMode                  = "Automatic"  #Manual (Automatic is only allowed in SynchronousCommit, not in AsynchronousCommit)
                    EndpointHostName              = $Nodes.NonNodeData.SqlServerSecondary            
                    PsDscRunAsCredential          = $DomainAdminCredential
                    DependsOn                     = $FarmTask 
                }
                $FarmTask = "[SqlAGReplica]AddReplicaSCOMSecondary"

                SqlAGReplica AddReplicaSCOMThird
                {
                    Ensure                        = 'Present'
                    Name                          = $Nodes.NonNodeData.SqlServerThird
                    AvailabilityGroupName         = $SqlServerAG
                    ServerName                    = $Nodes.NonNodeData.SqlServerThird
                    InstanceName                  = $Config.InstanceName 
                    ProcessOnlyOnActiveNode       = $false
                    PrimaryReplicaServerName      = $Nodes.NonNodeData.SqlServerPrimary
                    PrimaryReplicaInstanceName    = $Config.InstanceName
                    AvailabilityMode              = "SynchronousCommit" # AsynchronousCommit (SynchronousCommit only allows 3, rest should be AsynchronousCommit)
                    BackupPriority                = 50
                    ConnectionModeInPrimaryRole   = "AllowAllConnections"
                    ConnectionModeInSecondaryRole = "AllowAllConnections"
                    FailoverMode                  = "Automatic"  #Manual (Automatic is only allowed in SynchronousCommit, not in AsynchronousCommit)
                    EndpointHostName              = $Nodes.NonNodeData.SqlServerThird            
                    PsDscRunAsCredential          = $DomainAdminCredential
                    DependsOn                     = $FarmTask 
                }
                $FarmTask = "[SqlAGReplica]AddReplicaSCOMThird"

                SqlDatabaseRecoveryModel OperationsManager
                {
                    Name                  = $OperationsManagerDBName
                    RecoveryModel         = 'Full'
                    ServerName            = $Nodes.NonNodeData.SqlServerPrimary
                    InstanceName          = $Config.InstanceName
                    PsDscRunAsCredential  = $DomainAdminCredential
                    DependsOn             = $FarmTask 
                }
                $FarmTask = "[SqlDatabaseRecoveryModel]OperationsManager"

                SqlDatabaseRecoveryModel OperationsManagerDW
                {
                    Name                 = $OperationsManagerDWDBName
                    RecoveryModel        = 'Full'
                    ServerName           = $Nodes.NonNodeData.SqlServerPrimary
                    InstanceName         = $Config.InstanceName
                    PsDscRunAsCredential = $DomainAdminCredential
                    DependsOn            = $FarmTask 
                }
                $FarmTask = "[SqlDatabaseRecoveryModel]OperationsManagerDW"

                SqlAGDatabase Membership
                {
                    Ensure                  = 'Present'
                    AvailabilityGroupName   = $SqlServerAG
                    BackupPath              = $Config.SQLAGBackup
                    DatabaseName            = "$OperationsManagerDBName", "$OperationsManagerDWDBName"
                    InstanceName            = $Config.InstanceName
                    ServerName              =  $Nodes.NonNodeData.SqlServerPrimary
                    #ProcessOnlyOnActiveNode = $true
                    PsDscRunAsCredential    = $DomainAdminCredential 
                    DependsOn               = $FarmTask 
                }
                $FarmTask = "[SqlAGDatabase]Membership"
            }
            
            <#
            xSCOMManagementPack sqlpack
            {
            Name= "SQL 2016 Management Pack"
            SCOMAdminCredential = $DomainAdminCredential
            SourcePath = "C:\"
            SourceFolder = "\SCOM"
            SourceFile = "SQLServer2016MP.msi"
            PsDscRunAsCredential = $DomainAdminCredential        
            }

            $BasePath = "\\VD201\Share\SCOM\MPFiles\"
            $MPList = Get-ChildItem $BasePath -Recurse -Name "*mp*"
                    
            foreach ($MP in $MPList) {           
            $ManagementPack = $BasePath + $MP
            Write-Host $ManagementPack 
            If (Test-Path ("$ManagementPack"))
                    {Import-SCManagementPack "$ManagementPack"}
            }

            install Microsoft SQL Server Management Studio Management Pack for System Operation Center 2016 
            Package SQLmanagementPack
            {
            Ensure = "Present"   
            Name = "Microsoft System Center Management Pack for SQL Server 2016"
            Path = $Config.SQL2016ManagedPack          
            ProductId = $Config.SQL2016ManagedPackProductID
            Arguments = "/quiet /norestart"
            PsDscRunAsCredential = $DomainAdminCredential
                LogPath = [string] 
            DependsOn = "[xSCOMManagementServerSetup]OMMS"            
            }  
            #>        
        }
        elseif ($ServiceName -eq "OOS"){

            if($joinDomain){
                $DnsRecords =  $ConfigData.DnsRecords            
                foreach ($DnsRecord in $DnsRecords) {  
                    xDnsRecord $DnsRecord.prefix
                    {
                        Name        = $DnsRecord.prefix
                        Target      = $DnsRecord.IP
                        Zone        = $DomainName
                        Type        = "ARecord"
                        DnsServer   = $DNSServer
                        Ensure      = "Present"
                        PsDscRunAsCredential = $DomainAdminCredential                  
                    }
                }
            }
        }
        elseif ($ServiceName -eq "SharePoint") 
        {
            ##  BUILD SHAREPOINT SQL CLUSTER
            
            #$ConfigData | ConvertTo-Json |  Out-File -FilePath C:\ConfigData.txt
            #$ConfigData | Out-File -FilePath C:\json.txt

            $SqlAdministratorCredential = $InstallCredential
            $SqlServiceCredential       = $InstallCredential   
            $SqlAgentServiceCredential  = $InstallCredential
            
            #$ServerSite | Out-File -FilePath C:\ServerSite.txt

            $Nodes         = $ConfigData.Nodes  # $ConfigData[$ServerSite] not site specific Availibility group any more, one giant AG replicas
            $NonNodeData   = $ConfigData.NonNodeData
            $Settings      = $ConfigData.DatabaseSettings

            #$Nodes | ConvertTo-Json | Out-File -FilePath C:\Nodes.txt

            $Node = $Nodes.Where{$_.Name -eq $ServerName} 
            
            #$Node | ConvertTo-Json | Out-File -FilePath C:\Node.txt

            $ClusterIPAddress = $NonNodeData.ClusterIPAddress
            $ClusterName      = $NonNodeData.ClusterName
        
            $ClusterNodes = @();

            $Nodes.foreach({
                $ClusterNodes += $_.Name
            });

            # xCredSSP CredSSPServer
            # {
            #     Ensure = 'Present'
            #     Role = 'Server'
            # }

            # xCredSSP CredSSPClient
            # {
            #     Ensure = 'Present'
            #     Role = 'Client'
            #     DelegateComputers = "*.$($DomainName)"
            # }
                            
            @(
                "Failover-clustering",
                "RSAT-Clustering-PowerShell",
                "RSAT-Clustering-CmdInterface",
                "RSAT-Clustering-Mgmt"
            ) | ForEach-Object -Process {
                WindowsFeature "SP-Feature-$_"
                {
                    Ensure      = "Present"
                    Name        = $_
                    DependsOn   = $FarmTask 
                }
                $FarmTask = "[WindowsFeature]SP-Feature-$_"
            }          

            if ( $Node.Role -eq 'FirstServer' )      
            {                 
                WaitForAll ClusterFeature
                {
                    ResourceName            = '[WindowsFeature]SP-Feature-RSAT-Clustering-CmdInterface'
                    NodeName                = $Nodes.Name
                    RetryCount              = $RetryCount
                    RetryIntervalSec        = $RetryIntervalSec
                    PsDscRunAsCredential    = $InstallCredential
                    DependsOn               = $FarmTask 
                }
                $FarmTask = "[WaitForAll]ClusterFeature"
                
                Script CreateCluster
                {
                    SetScript = {
                            $ClusterService = Get-Service "ClusSvc"
                        
                        If($ClusterService) 
                            {
                                New-Cluster $using:ClusterName -Node $using:ClusterNodes -StaticAddress $using:ClusterIPAddress -NoStorage -AdministrativeAccessPoint Dns
                            }
                            #Get-Cluster -Name 'mc21'  | Add-ClusterNode -Name "VS222"
                            #Get-Cluster -Name MyCl1 | Add-ClusterNode -Name node3

                    }
                    TestScript = {  
                                    $ClusterService = Get-Service "ClusSvc"

                                    If($ClusterService) 
                                    {
                                        if($ClusterService.StartType -ne "Disabled")
                                        {
                                            if(Get-Cluster) {
                                            return $true
                                            }
                                            else{return $true}
                                        }
                                        else
                                        {
                                            return $false
                                        }                                 
                                    }
                                    else {return $true}
                    
                    }

                    GetScript = { $null }                    
                    PsDscRunAsCredential  =  $InstallCredential     
                    DependsOn   = $FarmTask 
                }
                $FarmTask = "[Script]CreateCluster"
            }

            if($joinDomain){
                $DnsRecords =  $ConfigData.DnsRecords
                foreach ($DnsRecord in $DnsRecords) {  
                    xDnsRecord $DnsRecord.prefix
                    {
                        Name        = $DnsRecord.prefix
                        Target      = $DnsRecord.IP
                        Zone        = $DomainName
                        Type        = "ARecord"
                        DnsServer   = $DNSServer
                        Ensure      = "Present"
                        PsDscRunAsCredential = $DomainAdminCredential                  
                    }
                }
            }

        }
     
    }
}