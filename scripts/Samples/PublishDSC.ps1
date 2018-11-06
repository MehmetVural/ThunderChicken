

#Connect-AzureRmAccount

Import-AzureRmAutomationDscConfiguration -SourcePath 'C:\github\ThunderChicken\scripts\Samples\TestDSCConfig.ps1' -ResourceGroupName 'ThunderChicken' -AutomationAccountName 'AzureDSCAccount' -Published -Force

Start-AzureRmAutomationDscCompilationJob -ConfigurationName 'TestDSCConfig' -ResourceGroupName 'ThunderChicken' -AutomationAccountName 'AzureDSCAccount'

#Register-AzureRmAutomationDscNode -ResourceGroupName 'ThunderChicken' -AutomationAccountName 'AzureDSCAccount' -AzureVMName 'master-dc2vm'

Register-AzureRmAutomationDscNode -ResourceGroupName 'ThunderChicken' -AzureVMResourceGroup "contosogroup" -AutomationAccountName 'AzureDSCAccount' -AzureVMName 'master-dc2vm' -ConfigurationMode 'ApplyandAutoCorrect' -AzureVMLocation "East US"

# Get the ID of the DSC node
$node = Get-AzureRmAutomationDscNode -ResourceGroupName 'ThunderChicken' -AutomationAccountName 'AzureDSCAccount' -Name 'master-dc2vm'

# Assign the node configuration to the DSC node
Set-AzureRmAutomationDscNode -ResourceGroupName 'ThunderChicken' -AutomationAccountName 'AzureDSCAccount' -NodeConfigurationName 'TestConfig.master-dc2vm' -Id $node.Id


# Get the ID of the DSC node
$node = Get-AzureRmAutomationDscNode -ResourceGroupName 'ThunderChicken' -AutomationAccountName 'AzureDSCAccount' -Name 'master-dc2vm'

# Get an array of status reports for the DSC node
$reports = Get-AzureRmAutomationDscNodeReport -ResourceGroupName 'ThunderChicken' -AutomationAccountName 'AzureDSCAccount' -Id $node.Id

# Display the most recent report
$reports[0]