
# Change NodeName with you own enviornment nodes and add addtional nodes if necessary 

@{
    AllNodes    = @(
        @{
            NodeName                    = "*"            
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser        = $true
        },
        @{ 
            NodeName  = "VS221"            
            Role      = "FirstServerNode"
        },
        @{ 
            NodeName  = "VS222"            
            Role      = "AdditionalServerNode"
        }
    )
    
    NonNodeData  = @{
        DomainDetails = @{
            DomainName  = "Domain.com"
            NetbiosName = "LAB"
        }
        ClusterName                 = 'V-Cluster'
        ClusterIPAddress            = '10.0.0.150/24'
        InstanceName                = 'MSSQLSERVER'
        AvailabilityGroupName    = "TestAG"
        TestDBName               = "TestDB"  
        ShareFolder = "\\VD201\Share"
        SQLAGBackup = "\\VD201\SQLAGBackup"
        SQLInstalISO = "\\VD201\Share\SharedSQL\en_sql_server_2016_enterprise_with_service_pack_2_x64_dvd_12124051.iso"
        SQLManagementStudio2017Path = "\\VD201\Share\SharedSQL\SSMS.17.9.1\SSMS-Setup-ENU.exe"
        SQLManagementStudio2017ProductId = "91a1b895-c621-4038-b34a-01e7affbcb6b"
        SQLManagementStudio2016Path = "\\vd201\Share\SharedSQL\SSMS.16.5.3\SSMS-Setup-ENU.exe"
        SQLManagementStudio2016ProductId= "2d1a30f7-a163-4aa7-a10e-e936aeba38fe"
        #Microsoft SQL Server Management Studio - 16.5.3
    }      
}