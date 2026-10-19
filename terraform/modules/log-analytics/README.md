# log-analytics

**What this demonstrates:** a Log Analytics workspace with retention and ingestion-cap controls, plus a helper that attaches a uniform "all logs and metrics" diagnostic setting to any list of resource IDs.

## Structure

| File | Purpose |
|------|---------|
| `main.tf` | Workspace and the `for_each` diagnostic settings helper |
| `variables.tf` | SKU, retention (30-730), daily quota, public access flags, `diagnostic_targets` map |
| `outputs.tf` | Resource ID, name, workspace GUID and the helper setting IDs |
| `versions.tf` | Terraform and provider version constraints |

## Usage

```hcl
module "log_analytics" {
  source              = "../../modules/log-analytics"
  name                = module.naming.log_analytics_workspace
  resource_group_name = module.resource_group.name
  retention_in_days   = 90
  daily_quota_gb      = -1

  diagnostic_targets = {
    aks = azurerm_kubernetes_cluster.this.id
  }
}
```

Validate on its own with `terraform -chdir=terraform/modules/log-analytics init -backend=false && terraform -chdir=terraform/modules/log-analytics validate`.

## Design decisions

- Lower environments set a daily cap; it is the single most effective guard against an accidental debug-logging bill.
- The helper uses the `allLogs` category group rather than listing categories, so it keeps working when Azure adds categories to a resource type.
- Service modules in this repository forward their own diagnostics (they know their categories); the helper is for resources created elsewhere or onboarded in bulk.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Log Analytics workspace name. | `string` | n/a | yes |
| `resource_group_name` | Resource group the workspace is created in. | `string` | n/a | yes |
| `location` | Azure region. | `string` | `uksouth` | no |
| `sku` | Pricing tier. PerGB2018 is pay-as-you-go; CapacityReservation suits predictable high-volume environments. | `string` | `PerGB2018` | no |
| `retention_in_days` | Interactive retention in days (30-730). | `number` | `30` | no |
| `daily_quota_gb` | Daily ingestion cap in GB. -1 disables the cap. Lower environments should always set a cap. | `number` | `-1` | no |
| `internet_ingestion_enabled` | Allow ingestion over the public internet. Disable when Azure Monitor Private Link Scope is in use. | `bool` | `true` | no |
| `internet_query_enabled` | Allow queries over the public internet. | `bool` | `true` | no |
| `diagnostic_targets` | Map of friendly name to resource ID. A diagnostic setting sending all logs and metrics to this workspace is created for each entry. | `map(string)` | `{}` | no |
| `diagnostic_log_category_group` | Log category group sent by the diagnostic settings helper. allLogs or audit. | `string` | `allLogs` | no |
| `tags` | Tags applied to the workspace. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Workspace resource ID (used by diagnostic settings). |
| `name` | Workspace name. |
| `workspace_id` | Workspace (customer) GUID used by agents and the Data Collector API. |
| `diagnostic_setting_ids` | Map of diagnostic setting IDs created by the helper, keyed by target name. |
