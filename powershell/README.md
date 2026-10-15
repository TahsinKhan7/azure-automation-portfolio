# PowerShell Automation

Operational automation for the data platform: Entra ID group hygiene, Databricks
token rotation and workspace provisioning, Key Vault and storage audits, Power BI
administration, Azure DevOps variable groups and release annotations.

Everything that contains logic lives in one module, `DataPlatform.Automation`.
The scripts in the folders below are thin, parameterised wrappers around that
module so that the logic is unit-tested once and reused everywhere (pipelines,
runbooks, interactive use).

## What this demonstrates

- A proper PowerShell module layout (`.psd1` manifest, `.psm1` loader,
  `Public/` and `Private/` function files, explicit `FunctionsToExport`).
- Scripts that are safe to run: `SupportsShouldProcess` everywhere a change is
  made, `-WhatIf` honoured end to end, secrets handled as `SecureString`, no
  `Write-Host`.
- Pester tests that mock the Az cmdlets, so the suite runs in CI without any
  Azure credentials or the Az modules installed.
- PSScriptAnalyzer as a gate rather than a suggestion, with the formatting
  rules switched on and no global exclusions.

## Structure

| Path | Contents |
|------|----------|
| `modules/DataPlatform.Automation/` | The module. See its [README](modules/DataPlatform.Automation/README.md) for the function reference. |
| `tests/` | Pester 5 tests (`*.Tests.ps1`) plus `_TestHelper.ps1`, which imports the module and defines Az cmdlet stand-ins. |
| `PSScriptAnalyzerSettings.psd1` | Analyser settings used locally and in CI. |
| `azure-ad/` | Entra ID group and user automation. |
| `azure-devops/` | Azure DevOps variable groups and release annotations. |
| `databricks-api/` | Databricks jobs, Unity Catalog and token rotation over the REST API. |
| `powerbi/` | Power BI workspace administration and dataset refresh. |
| `storage/` | ADLS Gen2 folder layout and ACLs, storage account audit, Key Vault secret inventory. |
| `arm/` | ARM/Bicep deployment helpers (what-if, template tests, release plans). Documented in its own [README](arm/README.md). |
| `Get-AzureCostReport.ps1`, `New-AzureResourceGroup.ps1` | Subscription-level utilities. |

## Scripts

| Script | Purpose | Module functions used |
|--------|---------|-----------------------|
| `Get-AzureCostReport.ps1` | Cost breakdown by subscription, resource group and resource from Cost Management usage detail | `ConvertTo-DpCostSummary`, `Get-DpCostSummaryByResourceGroup`, `Get-DpTopCostDriver` |
| `New-AzureResourceGroup.ps1` | Standardised resource group with mandatory tags, optional lock and tag policy | `Get-DpResourceName`, `Test-DpTagCompliance` |
| `azure-ad/New-AzureADGroups.ps1` | Create Entra ID security groups (with members and nesting) from JSON | `Write-DpLog` |
| `azure-ad/Remove-StaleADGroupMembers.ps1` | Remove members who are not on the authoritative HR list | `Get-DpStaleGroupMember` |
| `azure-ad/Set-AzureRBAC.ps1` | Apply, remove or audit RBAC assignments from JSON | `Write-DpLog` |
| `azure-ad/Set-DatabricksWorkspaceUsers.ps1` | Provision Entra ID group members into Databricks via SCIM | `Get-DpDatabricksAccessToken`, `Invoke-DpDatabricksApi` |
| `azure-ad/Sync-AzureADUsers.ps1` | Bulk e-mail attribute updates, mirrored into Databricks | `Get-DpDatabricksAccessToken`, `Invoke-DpDatabricksApi` |
| `azure-devops/Set-PipelineVariableGroup.ps1` | Create or update a variable group idempotently from JSON, with Key Vault-backed secrets | `Compare-DpVariableGroup`, `Set-DpAdoVariableGroup`, `ConvertTo-DpSecureString` |
| `azure-devops/New-ReleaseAnnotation.ps1` | Post a release annotation to Application Insights from a pipeline | `New-DpReleaseAnnotation` |
| `databricks-api/Invoke-DatabricksJobAction.ps1` | List, trigger, monitor or create Databricks jobs (Jobs 2.1 API) | `Get-DpDatabricksAccessToken`, `Invoke-DpDatabricksApi` |
| `databricks-api/Set-UnityCatalog.ps1` | Audit or bootstrap a catalog, medallion schemas and grants | `Get-DpDatabricksAccessToken`, `Invoke-DpDatabricksApi` |
| `databricks-api/Update-DatabricksTokens.ps1` | Rotate PATs approaching expiry and store the new values in Key Vault | `Get-DpDatabricksToken`, `Get-DpTokenRotationPlan`, `New-DpDatabricksToken`, `Revoke-DpDatabricksToken`, `Set-DpKeyVaultSecret` |
| `powerbi/Invoke-PowerBIRefresh.ps1` | List gateways or trigger dataset refreshes | `Write-DpLog` |
| `powerbi/Set-PowerBIWorkspace.ps1` | Workspace audit, report listing, user add/remove | `Write-DpLog` |
| `storage/Export-KeyVaultSecrets.ps1` | Export secret metadata (never values) with expiry classification | `Get-DpKeyVaultSecretInventory`, `Get-DpSecretExpiryStatus` |
| `storage/Get-StorageAccountAudit.ps1` | Audit storage accounts against the security baseline | `Get-DpStorageAccountComplianceReport`, `Test-DpStorageAccountCompliance` |
| `storage/Set-DataLakeACLs.ps1` | Create the medallion folder hierarchy and apply group ACLs | `Get-DpMedallionFolderLayout`, `ConvertTo-DpDataLakeAclPlan` |

### Renamed scripts

Four scripts previously used verbs that are not on the
[approved verb list](https://learn.microsoft.com/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands),
which PSScriptAnalyzer reports as `PSUseApprovedVerbs`. They have been renamed;
the behaviour is unchanged and each file's help notes its former name.

| Old name | New name |
|----------|----------|
| `databricks-api/Manage-DatabricksJobs.ps1` | `databricks-api/Invoke-DatabricksJobAction.ps1` |
| `databricks-api/Manage-UnityCatalog.ps1` | `databricks-api/Set-UnityCatalog.ps1` |
| `databricks-api/Rotate-DatabricksTokens.ps1` | `databricks-api/Update-DatabricksTokens.ps1` |
| `powerbi/Manage-PowerBIWorkspaces.ps1` | `powerbi/Set-PowerBIWorkspace.ps1` |

## Running a script

Every script imports the module from its relative path, so the repository can
be cloned and used without installing anything beyond the Az modules.

```powershell
Connect-AzAccount -Tenant 00000000-0000-0000-0000-000000000000

# Preview first; nothing is changed with -WhatIf.
./powershell/databricks-api/Update-DatabricksTokens.ps1 `
    -WorkspaceUrl https://adb-0000000000000000.0.azuredatabricks.net `
    -KeyVaultName kv-dp-data-dev-01 -TokenSecretName dbx-token-dev -WhatIf

./powershell/storage/Export-KeyVaultSecrets.ps1 -VaultName kv-dp-data-prod-01 -WarningDays 30 -OutputPath ./secrets.csv
```

Scripts write progress to the Information stream (`-InformationAction Continue`
or `$InformationPreference = 'Continue'` to see it) and return objects, so output
can be piped to `Export-Csv`, `ConvertTo-Json` or a pipeline log without parsing
text.

## Running the tests and the analyser locally

```powershell
Install-Module -Name Pester -MinimumVersion 5.5 -Scope CurrentUser
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser

# Same commands CI runs.
Invoke-ScriptAnalyzer -Path powershell -Recurse -Settings powershell/PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path powershell/tests -CI
```

The tests never call Azure. `tests/_TestHelper.ps1` defines stand-in functions
for the handful of Az cmdlets the module calls (`Get-AzKeyVaultSecret`,
`Set-AzKeyVaultSecret`, `Get-AzStorageAccount`, `Set-AzContext`,
`Get-AzAccessToken`) when the real cmdlets are not installed, and each test
replaces them with `Mock`. REST calls go through two small private functions
(`Invoke-DpDatabricksApi` is public, `Invoke-DpAdoApi` private) that wrap
`Invoke-RestMethod`, which the tests mock in the module scope.

| Test file | Covers | Tests |
|-----------|--------|-------|
| `tests/Naming.Tests.ps1` | `Get-DpResourceName`, `Test-DpTagCompliance` | 14 |
| `tests/CostReport.Tests.ps1` | Cost aggregation and top-N drivers | 7 |
| `tests/StaleMembers.Tests.ps1` | Stale member detection and safety rails | 6 |
| `tests/DataLakeAcl.Tests.ps1` | Medallion layout and ACL plan ordering | 7 |
| `tests/TokenRotation.Tests.ps1` | Rotation plan, Databricks API wrappers, Key Vault writes | 10 |
| `tests/StorageCompliance.Tests.ps1` | Storage baseline checks and subscription report | 8 |
| `tests/SecretExpiry.Tests.ps1` | Expiry classification and metadata-only inventory | 6 |
| `tests/AzureDevOps.Tests.ps1` | Variable group diff/apply and release annotations | 14 |

## Azure DevOps pipeline step

```yaml
- task: PowerShell@2
  displayName: Lint and test PowerShell
  inputs:
    pwsh: true
    targetType: inline
    script: |
      Install-Module Pester, PSScriptAnalyzer -Force -Scope CurrentUser
      $findings = Invoke-ScriptAnalyzer -Path powershell -Recurse -Settings powershell/PSScriptAnalyzerSettings.psd1
      $findings | Format-Table -AutoSize
      if ($findings | Where-Object Severity -eq 'Error') { throw 'PSScriptAnalyzer reported errors.' }
      Invoke-Pester -Path powershell/tests -CI
```

## Design decisions

- **Module plus wrappers, not standalone scripts.** Each wrapper is mostly a
  `param` block, an `Import-Module` and a few calls. The decision logic
  (which tokens to rotate, which members are stale, whether a storage account
  is compliant) is pure and tested in isolation.
- **Secrets stay `SecureString` until the last moment.** Tokens are read from
  Key Vault as `SecureString`, converted to plain text only inside the private
  header builders, and never logged. `ConvertTo-DpSecureString` is the single
  place a plain-text value is wrapped, with a documented analyser suppression.
- **Metadata, not values.** The Key Vault inventory and export only ever read
  secret attributes; the test suite asserts that `-AsPlainText` is never used.
- **Idempotent by construction.** Variable group updates compute a change set
  first; ACL and folder operations are planned before they are applied; every
  destructive step passes through `ShouldProcess`.
- **Naming parity with Terraform.** `Get-DpResourceName` produces the same
  names as `terraform/modules/naming`, so scripts and infrastructure agree on
  what a resource is called.

## Requirements

- PowerShell 7.0 or later (`CompatiblePSEditions = Core`).
- Az modules for the scripts that call Azure directly: `Az.Accounts`,
  `Az.Resources` (resource groups, locks, policy, RBAC and the `*-AzAD*`
  Entra ID cmdlets), `Az.KeyVault`, `Az.Storage` (including the
  `*-AzDataLakeGen2*` cmdlets) and `Az.Billing` (`Get-AzConsumptionUsageDetail`).
- `MicrosoftPowerBIMgmt` for the Power BI scripts.
- Pester 5.5+ and PSScriptAnalyzer 1.21+ to run the tests and the analyser.
