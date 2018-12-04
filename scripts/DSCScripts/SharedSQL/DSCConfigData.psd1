
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
            Role      = 'SQLServer'
        },
        @{ 
            NodeName  = "VS222"            
            Role      = "SQLServer"            
        }
    )
    NonNodeData = @{
        DomainDetails = @{
            DomainName  = "Domain.com"
            NetbiosName = "LAB"
        }
        ShareFolder = "\\VD201\Share"
    }      
}