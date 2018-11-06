configuration TestDSCConfig {
    Node master-dc2vm {
       WindowsFeature IIS {
          Ensure               = 'Present'
          Name                 = 'Web-Server'
          IncludeAllSubFeature = $true
       }
    }
 }
 