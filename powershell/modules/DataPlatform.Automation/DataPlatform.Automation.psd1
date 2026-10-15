@{
    RootModule           = 'DataPlatform.Automation.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = '7f4b9a2e-3c61-4d8a-9e5f-2b1c0d6a8e47'
    Author               = 'Tahsin Khan'
    CompanyName          = 'Independent'
    Copyright            = '(c) Tahsin Khan. Licensed under the MIT licence.'
    Description          = 'Reusable, testable automation functions for an Azure data platform: naming and tag governance, cost reporting, Entra ID group hygiene, ADLS Gen2 ACL planning, Databricks token rotation, storage and Key Vault compliance, Azure DevOps variable groups and release annotations.'
    PowerShellVersion    = '7.0'
    CompatiblePSEditions = @('Core')

    # Az.* and MicrosoftPowerBIMgmt are consumed at run time by a subset of
    # functions and are deliberately not declared as RequiredModules so that
    # the pure functions can be imported and tested without them.

    FunctionsToExport    = @(
        'Compare-DpVariableGroup'
        'ConvertTo-DpCostSummary'
        'ConvertTo-DpDataLakeAclPlan'
        'ConvertTo-DpReleaseAnnotationBody'
        'ConvertTo-DpSecureString'
        'Get-DpCostSummaryByResourceGroup'
        'Get-DpDatabricksAccessToken'
        'Get-DpDatabricksToken'
        'Get-DpKeyVaultSecretInventory'
        'Get-DpMedallionFolderLayout'
        'Get-DpResourceName'
        'Get-DpSecretExpiryStatus'
        'Get-DpStaleGroupMember'
        'Get-DpStorageAccountComplianceReport'
        'Get-DpTokenRotationPlan'
        'Get-DpTopCostDriver'
        'Invoke-DpDatabricksApi'
        'New-DpDatabricksToken'
        'New-DpReleaseAnnotation'
        'Revoke-DpDatabricksToken'
        'Set-DpAdoVariableGroup'
        'Set-DpKeyVaultSecret'
        'Test-DpStorageAccountCompliance'
        'Test-DpTagCompliance'
        'Write-DpLog'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @('Azure', 'Databricks', 'DataFactory', 'KeyVault', 'AzureDevOps', 'Governance')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/tahsinkhan/azure-automation-portfolio'
            ReleaseNotes = 'Initial release: logic extracted from standalone scripts into testable functions.'
        }
    }
}
