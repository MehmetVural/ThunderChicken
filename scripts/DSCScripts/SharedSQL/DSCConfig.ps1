
Configuration DSCConfig { 
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $SqlInstallCredential,

        [Parameter()]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $SqlAdministratorCredential = $SqlInstallCredential,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $SqlServiceCredential,

        [Parameter()]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $SqlAgentServiceCredential = $SqlServiceCredential
    )

    #If(Get-Module )
    #Install-Module  SqlServerDsc
    Import-DscResource -ModuleName SqlServerDsc
    Import-DscResource -ModuleName StorageDsc
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'

    Node $AllNodes.NodeName  {

        MountImage ISO
        {
            ImagePath   = 'c:\Sources\SQL.iso'
            DriveLetter = 'S'
        }

        WaitForVolume WaitForISO
        {
            DriveLetter      = 'S'
            RetryIntervalSec = 5
            RetryCount       = 10
        }
         #region Install SQL Server
         SqlSetup 'InstallDefaultInstance'
         {
             InstanceName         = 'MSSQLSERVER'
             Features             = 'SQLENGINE,AS'
             SQLCollation         = 'SQL_Latin1_General_CP1_CI_AS'
             SQLSvcAccount        = $SqlServiceCredential
             AgtSvcAccount        = $SqlAgentServiceCredential
             ASSvcAccount         = $SqlServiceCredential
             SQLSysAdminAccounts  = 'COMPANY\SQL Administrators', $SqlAdministratorCredential.UserName
             ASSysAdminAccounts   = 'COMPANY\SQL Administrators', $SqlAdministratorCredential.UserName
             InstallSharedDir     = 'C:\Program Files\Microsoft SQL Server'
             InstallSharedWOWDir  = 'C:\Program Files (x86)\Microsoft SQL Server'
             InstanceDir          = 'C:\Program Files\Microsoft SQL Server'
             InstallSQLDataDir    = 'E:\Data'
             SQLUserDBDir         = 'E:\Data'
             SQLUserDBLogDir      = 'F:\Logs'
             SQLTempDBDir         = 'E:\Data'
             SQLTempDBLogDir      = 'F:\Logs'
             SQLBackupDir         = 'H:\Backup' 
             ASServerMode         = 'TABULAR'
             ASConfigDir          = 'E:\MSOLAP\Config'
             ASDataDir            = 'E:\MSOLAP\Data'
             ASLogDir             = 'F:\MSOLAP\Log'
             ASBackupDir          = 'H:\MSOLAP\Backup'
             ASTempDir            = 'G:\MSOLAP\Temp'            
             SourcePath           =  $NonNodeData.ShareFolder
             UpdateEnabled        = 'False'
             ForceReboot          = $true 
             PsDscRunAsCredential = $SqlInstallCredential           
         }
         #endregion Install SQL Server

         
    }
}
 