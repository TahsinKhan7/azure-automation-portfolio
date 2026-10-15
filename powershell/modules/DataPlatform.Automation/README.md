# DataPlatform.Automation

PowerShell module that holds the logic behind every script in `powershell/`.
The scripts are thin wrappers; this module is where decisions are made and
where the Pester tests point.

## Layout

| Path | Purpose |
|------|---------|
| `DataPlatform.Automation.psd1` | Manifest. Declares `PowerShellVersion = '7.0'`, `CompatiblePSEditions = @('Core')` and an explicit `FunctionsToExport` list, so nothing leaks by accident. |
| `DataPlatform.Automation.psm1` | Loader. Dot-sources every `Private/*.ps1` and `Public/*.ps1` file; the manifest decides what is exported. |
| `Public/` | One exported function per file, named after the function. |
| `Private/` | Helpers used only inside the module (header builders, REST wrappers, SecureString unwrapping). |

The Az and Power BI modules are deliberately **not** declared
as `RequiredModules`. The functions that need them call the cmdlets by name,
which keeps `Import-Module` fast and lets the test suite run with mocks on a
machine that has none of them installed.

## Importing

```powershell
Import-Module ./powershell/modules/DataPlatform.Automation/DataPlatform.Automation.psd1
Get-Command -Module DataPlatform.Automation
```

## Public functions

### Naming and tagging

| Function | Purpose |
|----------|---------|
| `Get-DpResourceName` | Returns the standard name for a resource type, matching `terraform/modules/naming` (for example `rg-dp-data-prod-uks-01`, `stdpdataprod01`, `kv-dp-data-prod-01`). |
| `Test-DpTagCompliance` | Checks a tag set against the platform's mandatory tags and value rules and returns the missing or invalid tags. |

### Cost

| Function | Purpose |
|----------|---------|
| `ConvertTo-DpCostSummary` | Aggregates Cost Management usage detail rows into one row per resource, with costs rounded to two decimal places. |
| `Get-DpCostSummaryByResourceGroup` | Rolls per-resource rows up to subscription, month and resource group. |
| `Get-DpTopCostDriver` | Returns the N most expensive rows from a cost summary. |

### Entra ID

| Function | Purpose |
|----------|---------|
| `Get-DpStaleGroupMember` | Identifies group members who are not on the authorised (HR) user list. Throws when the authorised list is empty so an upstream failure can never empty a group. |

### Data lake

| Function | Purpose |
|----------|---------|
| `Get-DpMedallionFolderLayout` | Returns the bronze/silver/gold folder hierarchy (parents before children) plus the system folders. |
| `ConvertTo-DpDataLakeAclPlan` | Turns ACL rules (group, permissions, paths) into a list of ACL entries ordered so that parent paths are applied before their children. |

### Databricks

| Function | Purpose |
|----------|---------|
| `Get-DpDatabricksAccessToken` | Reads a Databricks token from Key Vault as a `SecureString`. |
| `Invoke-DpDatabricksApi` | Calls a Databricks REST endpoint with a bearer token; the one place `Invoke-RestMethod` is called for Databricks, so tests can mock it. |
| `Get-DpDatabricksToken` | Lists the personal access tokens visible to the calling identity. |
| `New-DpDatabricksToken` | Creates a PAT and returns its value as a `SecureString`. |
| `Revoke-DpDatabricksToken` | Revokes a PAT by ID. |
| `Get-DpTokenRotationPlan` | Decides which tokens to rotate, keep or treat as expired, given a warning window and a reference time. |

### Key Vault

| Function | Purpose |
|----------|---------|
| `Set-DpKeyVaultSecret` | Writes a secret with a content type and optional expiry; supports `-WhatIf`. |
| `Get-DpSecretExpiryStatus` | Classifies an expiry date as `Valid`, `Expiring Soon`, `Expired` or `No Expiry Set`. |
| `Get-DpKeyVaultSecretInventory` | Lists secret metadata (never values) for a vault with the expiry classification attached. |
| `ConvertTo-DpSecureString` | The single sanctioned plain-text-to-`SecureString` conversion, for values that already arrived in memory (API responses, pipeline variables). |

### Storage

| Function | Purpose |
|----------|---------|
| `Test-DpStorageAccountCompliance` | Evaluates one storage account against the baseline: HTTPS only, TLS 1.2, no anonymous blob access, default-deny network rules, optionally shared key disabled and a set of required tags. |
| `Get-DpStorageAccountComplianceReport` | Runs the check across every storage account in a subscription. |

### Azure DevOps and Application Insights

| Function | Purpose |
|----------|---------|
| `Compare-DpVariableGroup` | Computes the add/update/remove change set between a live variable group and the desired state. |
| `Set-DpAdoVariableGroup` | Creates or updates a variable group idempotently through the REST API, applying only the computed change set. |
| `ConvertTo-DpReleaseAnnotationBody` | Builds the request body for an Application Insights release annotation. |
| `New-DpReleaseAnnotation` | Posts a release annotation so deployments appear on Azure Monitor charts. |

### Logging

| Function | Purpose |
|----------|---------|
| `Write-DpLog` | Timestamped message to the Information stream (or Warning / Verbose by level). No `Write-Host`, so output stays capturable. |

## Private functions

| Function | Purpose |
|----------|---------|
| `ConvertFrom-DpSecureString` | Unwraps a `SecureString` immediately before it goes into an HTTP header. |
| `Get-DpBearerHeader` | Builds `Authorization: Bearer` and `Content-Type` headers. |
| `Get-DpAdoBasicHeader` | Builds the Basic authentication header Azure DevOps expects for a PAT. |
| `Invoke-DpAdoApi` | Thin wrapper around `Invoke-RestMethod` for the Azure DevOps REST API. |
| `Get-DpResourceGroupFromResourceId` | Extracts the resource group name from an Azure resource ID. |

## Conventions

- Every function has comment-based help with at least a synopsis and an example.
- Functions that change state declare `SupportsShouldProcess` and call
  `$PSCmdlet.ShouldProcess` before the change.
- Parameters are typed and validated (`ValidateSet`, `ValidatePattern`,
  `ValidateRange`) so bad input fails at binding time rather than mid-run.
- Secrets are `[securestring]` parameters; the only plain-text conversion is in
  `ConvertTo-DpSecureString`, which carries an analyser suppression with a
  justification.
- Pure functions (plans, classifications, aggregations) take their inputs as
  objects and a reference `-Now` where time matters, so they are deterministic
  under test.

## Adding a function

1. Create `Public/Verb-DpNoun.ps1` (approved verb, `Dp` prefix) containing a
   single function with comment-based help.
2. Add the name to `FunctionsToExport` in the manifest.
3. Add or extend a test file under `powershell/tests/`.
4. Run the analyser and the tests:

   ```powershell
   Invoke-ScriptAnalyzer -Path powershell -Recurse -Settings powershell/PSScriptAnalyzerSettings.psd1
   Invoke-Pester -Path powershell/tests -CI
   ```
