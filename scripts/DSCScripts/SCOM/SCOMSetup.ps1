
Configuration SCOMSetup { 
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $InstallCredential        
    )

    #If(Get-Module )
    #Install-Module  SqlServerDsc
    #if (Get-Module -ListAvailable -Name SqlServerDsc)
    #{ Install-Module SqlServerDsc }

    Import-DscResource -ModuleName SqlServerDsc
    Import-DscResource -ModuleName StorageDsc
    Import-DscResource -ModuleName xCredSSP
    Import-DscResource -Module xSCOM -ModuleVersion "1.3.3.1"
    Import-DscResource -ModuleName NetworkingDsc
    Import-DscResource -ModuleName PSDesiredStateConfiguration

    Node $AllNodes.NodeName  {
        
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
            WindowsFeature "Feature-$_"
            {
                Ensure = "Present"
                Name = $_
            }
        }

        @(            
            "RSAT-AD-PowerShell"            
        ) | ForEach-Object -Process {
            WindowsFeature "Feature-$_"
            {
                Ensure = "Present"
                Name = $_
            }
        }  
        
        # Prerequisties for SCOM report viewing
        Package "SQLServer2012SystemCLRTypes"
        {
            Ensure = "Present"
            Name = "Microsoft System CLR Types for SQL Server 2014"
            ProductId = $ConfigurationData.NonNodeData.SysClrTypesProductID
            Path = $ConfigurationData.NonNodeData.SQLSysClrTypesSource
            Arguments = "ALLUSERS=2"
            PsDscRunAsCredential = $InstallCredential
        }

        Package "ReportViewer2012Redistributable"
        {
            Ensure = "Present"
            Name = "Microsoft Report Viewer 2015 Runtime"
            ProductID = $ConfigurationData.NonNodeData.ReportViewerProductID
            Path = $ConfigurationData.NonNodeData.ReportViewerSource
            Arguments = "ALLUSERS=2"
            PsDscRunAsCredential = $InstallCredential
            DependsOn = "[Package]SQLServer2012SystemCLRTypes"
        }

        # Add service accounts to admins on Management Servers        
        # Group "Administrators"
        # {
        #    GroupName = "Administrators"
        #    MembersToInclude = @(
        #    Node.SystemCenter2012OperationsManagerActionAccount.UserName,
        #    $Node.SystemCenter2012OperationsManagerDASAccount.UserName
        # ) 

        if ( $Node.Role -eq 'Primary' )
        {
            # Install first Management Server
            xSCOMManagementServerSetup "OMMS"
            {
               DependsOn = @(
                            "[Package]SQLServer2012SystemCLRTypes",
                            "[Package]ReportViewer2012Redistributable"
                  )
               Ensure = "Present"
               SourcePath = $ConfigurationData.NonNodeData.SCOMSourcePath
               SourceFolder = ""
               SetupCredential = $InstallCredential
               ProductKey = ""      
               ManagementGroupName = $ConfigurationData.NonNodeData.ManagementGroupName
               FirstManagementServer = $true
               ActionAccount = $InstallCredential
               DASAccount = $InstallCredential
               DataReader = $InstallCredential
               DataWriter = $InstallCredential
               SqlServerInstance = $ConfigurationData.NonNodeData.SqlServerInstance
               #DatabaseName = "SCOMManager"
               #DatabaseSize = 100
               DwSqlServerInstance = $ConfigurationData.NonNodeData.DwSqlServerInstance
               #DwDatabaseName = $Node.SqlDWDatabase
               #DwDatabaseSize = $Node.DwDatabaseSize
               PsDscRunAsCredential = $InstallCredential

            }
        }

        if ( $Node.Role -eq 'Secondary' )
        {
            WaitForAll "OMMS"
            {
                NodeName = ( $AllNodes | Where-Object { $_.Role -eq 'Primary' } ).NodeName
                ResourceName = "[xSCOMManagementServerSetup]OMMS"
                PsDscRunAsCredential = $InstallCredential
                RetryCount = 1440
                RetryIntervalSec = 5
            }

            # Install additional Management Servers
            xSCOMManagementServerSetup "OMMS"
            {
               DependsOn = "[WaitForAll]OMMS", "[Package]SQLServer2012SystemCLRTypes", "[Package]ReportViewer2012Redistributable"
               Ensure = "Present"
               SourcePath = $ConfigurationData.NonNodeData.SCOMSourcePath
               SourceFolder = ""
               SetupCredential = $InstallCredential
               ManagementGroupName =  $ConfigurationData.NonNodeData.ManagementGroupName
               FirstManagementServer = $false
               ActionAccount = $InstallCredential
               DASAccount = $InstallCredential
               DataReader = $InstallCredential
               DataWriter = $InstallCredential
               SqlServerInstance = $ConfigurationData.NonNodeData.SqlServerInstance
               DwSqlServerInstance = $ConfigurationData.NonNodeData.DwSqlServerInstance
            }
        }

        xSCOMConsoleSetup "OMC"
        {
              DependsOn = @(
                        "[Package]SQLServer2012SystemCLRTypes",
                        "[Package]ReportViewer2012Redistributable",
                        "[xSCOMManagementServerSetup]OMMS"
              )
              Ensure = "Present"
              SourcePath = $ConfigurationData.NonNodeData.SCOMSourcePath
               SourceFolder = ""
              SetupCredential = $InstallCredential
              PsDscRunAsCredential = $InstallCredential
        }

        #xSCOMReportingServerSetup "OMRS"
        #{
        #    DependsOn = "[xSCOMManagementServerSetup]OMMS"
        #    Ensure = "Present"
        #    SourcePath = $ConfigurationData.NonNodeData.SCOMSourcePath
        #    SourceFolder = ""
        #    SetupCredential = $InstallCredential
        #    ManagementServer = $Node.NodeName 
        #    SRSInstance = $ConfigurationData.NonNodeData.SRSInstance
        #    DataReader = $InstallCredential
        #    PsDscRunAsCredential = $InstallCredential
        #}    

        xSCOMWebConsoleServerSetup "OMWC"
        {
            DependsOn = "[xSCOMManagementServerSetup]OMMS"
            Ensure = "Present"
            SourcePath = $ConfigurationData.NonNodeData.SCOMSourcePath
             SourceFolder = ""
            SetupCredential = $InstallCredential
            ManagementServer = $Node.NodeName
            PsDscRunAsCredential = $InstallCredential
        }
        
        #xSCOMManagementPack sqlpack
        #{
        #    Name= "SQL 2016 Management Pack"
        #    SCOMAdminCredential = $InstallCredential
        #    SourcePath = "C:\"
        #    SourceFolder = "\SCOM"
        #    SourceFile = "SQLServer2016MP.msi"
        #    PsDscRunAsCredential = $InstallCredential        
        #}

        #$BasePath = "\\VD201\Share\SCOM\MPFiles\"
        #$MPList = Get-ChildItem $BasePath -Recurse -Name "*mp*"
                
        #foreach ($MP in $MPList) {           
        #    $ManagementPack = $BasePath + $MP
        #    Write-Host $ManagementPack 
        #    If (Test-Path ("$ManagementPack"))
        #           {Import-SCManagementPack "$ManagementPack"}
        #}

        # install Microsoft SQL Server Management Studio Management Pack for System Operation Center 2016 
        #Package SQLmanagementPack
        #{
        #    Ensure = "Present"   
        #    Name = "Microsoft System Center Management Pack for SQL Server 2016"
        #    Path = $ConfigurationData.NonNodeData.SQL2016ManagedPack          
        #    ProductId = $ConfigurationData.NonNodeData.SQL2016ManagedPackProductID
        #    Arguments = "/quiet /norestart"
        #    PsDscRunAsCredential = $InstallCredential
            #LogPath = [string] 
        #    DependsOn = "[xSCOMManagementServerSetup]OMMS"            
        #}        
    }
}
 