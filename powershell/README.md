# PowerShell Automation Scripts

Scripts for managing Azure resources, Databricks workspaces, Azure AD, Key Vault, Storage and Power BI in enterprise environments.

## Azure AD (`azure-ad/`)

| Script | Purpose |
|--------|---------|
| `New-AzureADGroups.ps1` | Bulk create AD security groups with nested group support |
| `Remove-StaleADGroupMembers.ps1` | Remove stale users from AD groups based on HR authorisation list |
| `Set-AzureRBAC.ps1` | Manage Azure RBAC role assignments across subscriptions |
| `Set-DatabricksWorkspaceUsers.ps1` | Provision users to Databricks workspaces from AD group membership |
| `Sync-AzureADUsers.ps1` | Bulk update AD user attributes and sync to Databricks via SCIM |

## Databricks API (`databricks-api/`)

| Script | Purpose |
|--------|---------|
| `Rotate-DatabricksTokens.ps1` | Automated PAT rotation with Key Vault storage |
| `Manage-UnityCatalog.ps1` | Create catalogs, schemas and permissions in Unity Catalog |
| `Manage-DatabricksJobs.ps1` | List, trigger, monitor and create Databricks jobs |

## Storage & Key Vault (`storage/`)

| Script | Purpose |
|--------|---------|
| `Set-DataLakeACLs.ps1` | Manage ADLS Gen2 folder structures and POSIX ACL permissions |
| `Get-StorageAccountAudit.ps1` | Compliance audit across storage accounts (TLS, network rules, public access) |
| `Export-KeyVaultSecrets.ps1` | Export Key Vault secret metadata for expiry tracking and auditing |

## Power BI (`powerbi/`)

| Script | Purpose |
|--------|---------|
| `Manage-PowerBIWorkspaces.ps1` | Workspace audit, user management and report listing |
| `Invoke-PowerBIRefresh.ps1` | Gateway management and on-demand dataset refreshes |

## General

| Script | Purpose |
|--------|---------|
| `New-AzureResourceGroup.ps1` | Standardised resource group provisioning with tagging and policy |
| `Get-AzureCostReport.ps1` | Cost breakdown reports by subscription and resource group |

## Requirements

- PowerShell 7+
- Az PowerShell module (`Install-Module Az`)
- MicrosoftPowerBIMgmt module (for Power BI scripts)
- Appropriate Azure RBAC permissions
