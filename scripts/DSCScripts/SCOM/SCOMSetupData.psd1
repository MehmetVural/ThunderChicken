
# Change NodeName with you own enviornment nodes and add addtional nodes if necessary 

@{
    AllNodes    = @(
        @{
            NodeName                    = "*"            
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser        = $true
        },
        @{ 
            NodeName  = "VS201"
            Role      = 'Primary'
        }
        ,        
        @{ 
            NodeName  = "VS202"            
            Role      = 'Secondary'           
        }
    )

    NonNodeData  = @{
        DomainDetails = @{
            DomainName  = "Domain.com"
            NetbiosName = "LAB"
        }
        ShareFolder = "\\VD201\Share"        
        SCOMSourcePath = "\\VD201\Share\SCOM\SC 2016 RTM SCOM\"
        SQLSysClrTypesSource = "\\VD201\Share\SCOM\SQLSysClrTypes.msi"
        SysClrTypesProductID = "68BA34E8-9B9D-4A74-83F0-7D366B532D75"
        ReportViewerSource = "\\VD201\Share\SCOM\ReportViewer.msi"
        ReportViewerProductID = "3ECE8FC7-7020-4756-A71C-C345D4725B77" 
        SCOMProducKey = "" 
        ManagementGroupName = "SCOM"        
        SQL2016ManagedPack = "\\VD201\Share\SCOM\SQLServer2016MP.msi"
        SQL2016ManagedPackProductID = "2CCCD49C-7B9A-4703-A8AE-F28CDE94C126"                                       

        SqlServer  = "VS221"
        SqlServerInstance = "VS221\MSSQLSERVER"
        DwSqlServerInstance = "VS221\MSSQLSERVER"
        SRSInstance = "VS221\MSSQLSERVER"
        ModulesPath = "\\VD201\Share\SCOM\Modules\"        
        ManagementPacksPath = "\\VD201\Share\SCOM\ManagementPack\" 
    }      
}