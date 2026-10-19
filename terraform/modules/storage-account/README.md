# storage-account

**What this demonstrates:** a hardened ADLS Gen2 account for the lakehouse: hierarchical namespace, Shared Key disabled, OAuth by default, TLS 1.2, infrastructure encryption, deny-by-default firewall, medallion containers, lifecycle tiering and role assignments as inputs.

## Structure

| File | Purpose |
|------|---------|
| `main.tf` | Account, containers, lifecycle policy, role assignments, blob diagnostics |
| `variables.tf` | Name/container regexes, replication and tier lists, soft-delete ranges, lifecycle rule objects |
| `outputs.tf` | IDs, endpoints, identity, container names and ready-made `abfss://` URLs |
| `versions.tf` | Terraform and provider version constraints |

## Usage

```hcl
module "storage_account" {
  source              = "../../modules/storage-account"
  name                = module.naming.storage_account
  resource_group_name = module.resource_group.name
  replication_type    = "GZRS"
  containers          = ["bronze", "silver", "gold", "catalog"]

  lifecycle_rules = {
    bronze = { prefix_match = ["bronze/"], tier_to_cool_days = 90, tier_to_archive_days = 365 }
  }
}
```

Validate on its own with `terraform -chdir=terraform/modules/storage-account init -backend=false && terraform -chdir=terraform/modules/storage-account validate`.

## Design decisions

- Containers are created through `storage_account_id` (management plane) so a `Deny` firewall never blocks the pipeline agent during apply.
- Shared Key access is disabled by default; every consumer in this repository (Databricks access connector, Data Factory, AKS) authenticates with a managed identity.
- Soft delete uses dynamic blocks so a value of 0 removes the block entirely instead of sending an invalid configuration.
- Covered by `tests/storage_account.tftest.hcl`, which asserts the security posture with a mocked provider.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Storage account name (3-24 lowercase alphanumerics, globally unique). | `string` | n/a | yes |
| `resource_group_name` | Resource group the account is created in. | `string` | n/a | yes |
| `location` | Azure region. | `string` | `uksouth` | no |
| `account_tier` | Performance tier. | `string` | `Standard` | no |
| `replication_type` | Replication strategy. LRS/ZRS for lower environments, GRS/GZRS/RAGZRS for production. | `string` | `ZRS` | no |
| `access_tier` | Default blob access tier. | `string` | `Hot` | no |
| `containers` | Containers (ADLS Gen2 file systems) to create. Defaults to the medallion layers. | `list(string)` | `[bronze, silver, gold]` | no |
| `shared_access_key_enabled` | Allow Shared Key (account key) authentication. Keep false so that all access is through Entra ID. | `bool` | `false` | no |
| `public_network_access_enabled` | Allow access from public networks (subject to network_rules). Set false when private endpoints are deployed. | `bool` | `true` | no |
| `network_rules_default_action` | Default firewall action for traffic not matched by an IP or subnet rule. | `string` | `Deny` | no |
| `allowed_ip_ranges` | Public IPv4 addresses or CIDR ranges allowed through the firewall. /31 and /32 ranges are not accepted by Azure; use the bare address instead. | `list(string)` | `[]` | no |
| `allowed_subnet_ids` | Subnet IDs allowed through the firewall via the Microsoft.Storage service endpoint. | `list(string)` | `[]` | no |
| `blob_soft_delete_days` | Days deleted blobs are retained (1-365). 0 disables. | `number` | `30` | no |
| `container_soft_delete_days` | Days deleted containers are retained (1-365). 0 disables. | `number` | `30` | no |
| `lifecycle_rules` | Lifecycle tiering rules keyed by rule name. Blobs under prefix_match are moved to cool, then archive, then deleted after the given number of days since modification; null skips that step. | `map(...)` | `{bronze: {prefix_match: [bronze/], tier_to_cool_days: 90,...` | no |
| `blob_data_contributor_principal_ids` | Map of friendly name to principal object ID granted Storage Blob Data Contributor on the account (for example the Databricks access connector and the Data Factory identity). | `map(string)` | `{}` | no |
| `blob_data_reader_principal_ids` | Map of friendly name to principal object ID granted Storage Blob Data Reader on the account. | `map(string)` | `{}` | no |
| `enable_diagnostics` | Create the diagnostic setting. Kept separate from log_analytics_workspace_id so that the toggle is known at plan time even when the workspace is created in the same apply. | `bool` | `false` | no |
| `log_analytics_workspace_id` | Workspace ID for blob service diagnostics. Required when enable_diagnostics is true. | `string` | `null` | no |
| `tags` | Tags applied to the account. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Storage account resource ID. |
| `name` | Storage account name. |
| `primary_dfs_endpoint` | ADLS Gen2 (DFS) endpoint. |
| `primary_blob_endpoint` | Blob endpoint. |
| `principal_id` | Object ID of the account's system-assigned identity. |
| `container_names` | Names of the containers created. |
| `abfss_urls` | Map of container name to abfss:// URL, ready for Unity Catalog external locations. |
