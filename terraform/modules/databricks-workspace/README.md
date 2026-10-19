# databricks-workspace

**What this demonstrates:** a premium, VNet-injected Databricks workspace with secure cluster connectivity, optional private-only access, full diagnostic logging, and the Unity Catalog access connector (managed identity) with its storage role assignment.

## Structure

| File | Purpose |
|------|---------|
| `main.tf` | Workspace, access connector, storage role assignment, diagnostics |
| `variables.tf` | SKU, network inputs from the networking module, access toggles, diagnostics |
| `outputs.tf` | Resource ID, numeric workspace ID, URL, managed RG, access connector ID and principal |
| `versions.tf` | Terraform and provider version constraints |

## Usage

```hcl
module "databricks_workspace" {
  source                            = "../../modules/databricks-workspace"
  name                              = module.naming.databricks_workspace
  resource_group_name               = module.resource_group.name
  managed_resource_group_name       = module.naming.databricks_managed_resource_group
  vnet_id                           = module.networking.vnet_id
  public_subnet_name                = module.networking.databricks_public_subnet_name
  private_subnet_name               = module.networking.databricks_private_subnet_name
  public_subnet_nsg_association_id  = module.networking.databricks_public_subnet_nsg_association_id
  private_subnet_nsg_association_id = module.networking.databricks_private_subnet_nsg_association_id
  access_connector_name             = module.naming.databricks_access_connector
  assign_storage_role               = true
  storage_account_id                = module.storage_account.id
}
```

Validate on its own with `terraform -chdir=terraform/modules/databricks-workspace init -backend=false && terraform -chdir=terraform/modules/databricks-workspace validate`.

## Design decisions

- The access connector lives here (azurerm) rather than in the Unity Catalog module (databricks provider) so its storage role exists before any Databricks API call that validates an external location.
- `network_security_group_rules_required` follows `public_network_access_enabled`, which is the combination Azure requires for a private-only workspace.
- Diagnostics use the `allLogs` category group: Databricks has added categories (Unity Catalog, serverless) several times and a fixed list goes stale.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Databricks workspace name. | `string` | n/a | yes |
| `resource_group_name` | Resource group the workspace is created in. | `string` | n/a | yes |
| `location` | Azure region. | `string` | `uksouth` | no |
| `sku` | Workspace tier. premium is required for Unity Catalog, cluster policies and RBAC features used elsewhere in this repository. | `string` | `premium` | no |
| `managed_resource_group_name` | Name of the managed resource group Databricks creates for workspace infrastructure. | `string` | n/a | yes |
| `vnet_id` | ID of the VNet the workspace is injected into. | `string` | n/a | yes |
| `public_subnet_name` | Name of the delegated host subnet. | `string` | n/a | yes |
| `private_subnet_name` | Name of the delegated container subnet. | `string` | n/a | yes |
| `public_subnet_nsg_association_id` | NSG association ID of the host subnet. | `string` | n/a | yes |
| `private_subnet_nsg_association_id` | NSG association ID of the container subnet. | `string` | n/a | yes |
| `no_public_ip` | Enable secure cluster connectivity (clusters have no public IPs). Requires NAT gateway or firewall egress. | `bool` | `true` | no |
| `public_network_access_enabled` | Allow the workspace UI and APIs to be reached from the public internet. false requires a front-end private endpoint. | `bool` | `true` | no |
| `access_connector_name` | Name of the Databricks access connector whose managed identity Unity Catalog uses to reach storage. | `string` | n/a | yes |
| `assign_storage_role` | Grant the access connector Storage Blob Data Contributor on storage_account_id. | `bool` | `false` | no |
| `storage_account_id` | Storage account the access connector is granted Storage Blob Data Contributor on. Required when assign_storage_role is true. | `string` | `null` | no |
| `enable_diagnostics` | Create the diagnostic setting. Kept separate from log_analytics_workspace_id so that the toggle is known at plan time even when the workspace is created in the same apply. | `bool` | `false` | no |
| `log_analytics_workspace_id` | Workspace ID for workspace diagnostics (clusters, jobs, notebooks, Unity Catalog audit). Required when enable_diagnostics is true. | `string` | `null` | no |
| `tags` | Tags applied to the workspace and access connector. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Workspace Azure resource ID (used for the databricks provider's azure_workspace_resource_id). |
| `workspace_id` | Numeric Databricks workspace ID (used for metastore assignment and workspace bindings). |
| `workspace_url` | Workspace host, for example https://adb-1234567890123456.7.azuredatabricks.net. |
| `managed_resource_group_id` | ID of the Databricks managed resource group. |
| `access_connector_id` | Access connector resource ID (used by the Unity Catalog storage credential). |
| `access_connector_principal_id` | Object ID of the access connector's managed identity. |
