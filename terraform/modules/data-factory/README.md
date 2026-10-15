# data-factory

**What this demonstrates:** a Data Factory with a managed virtual network and managed-VNet integration runtime, a system-assigned identity used by every linked service (Key Vault, ADLS Gen2, Databricks), managed private endpoints, optional Azure DevOps Git integration for the development factory, and run diagnostics to Log Analytics.

## Structure

| File | Purpose |
|------|---------|
| `main.tf` | Factory, integration runtime, role assignments, linked services, managed private endpoints, diagnostics |
| `variables.tf` | Toggles for each linked service and role, cluster and IR shapes as objects, optional Git object |
| `outputs.tf` | ID, name, identity, IR name and the linked service names pipelines reference |
| `versions.tf` | Terraform and provider version constraints |

## Usage

```hcl
module "data_factory" {
  source              = "../../modules/data-factory"
  name                = module.naming.data_factory
  resource_group_name = module.resource_group.name
  environment         = var.environment
  key_vault_id        = module.key_vault.id

  assign_data_lake_role            = true
  data_lake_storage_account_id     = module.storage_account.id
  create_data_lake_linked_service  = true
  data_lake_dfs_endpoint           = module.storage_account.primary_dfs_endpoint
  create_databricks_linked_service = true
  databricks_workspace_url         = module.databricks_workspace.workspace_url
  databricks_workspace_id          = module.databricks_workspace.id

  git_configuration = var.environment == "dev" ? var.data_factory_git_configuration : null
}
```

Validate on its own with `terraform -chdir=terraform/modules/data-factory init -backend=false && terraform -chdir=terraform/modules/data-factory validate`.

## Design decisions

- Only the dev factory is Git-connected. Other environments receive the ARM template that the ADF publish step produces, so linked service names here match what that template expects.
- Linked services authenticate with the factory identity; no connection strings or tokens are stored in the factory.
- The Git tenant defaults to the deploying tenant via `azurerm_client_config`, which the provider requires but which should never be hard-coded.
- A global parameter `env` is exposed so pipelines can branch on environment without per-environment pipeline JSON.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Data Factory name (3-63 alphanumerics and hyphens, globally unique). | `string` | n/a | yes |
| `resource_group_name` | Resource group the factory is created in. | `string` | n/a | yes |
| `location` | Azure region. | `string` | `uksouth` | no |
| `environment` | Environment name exposed to pipelines as the global parameter env. | `string` | n/a | yes |
| `public_network_enabled` | Allow public access to the factory endpoints. Set false when a private endpoint is deployed. | `bool` | `true` | no |
| `key_vault_id` | Key Vault the factory reads connection secrets from. A linked service and a Key Vault Secrets User role assignment are created. | `string` | n/a | yes |
| `assign_data_lake_role` | Grant the factory identity Storage Blob Data Contributor on data_lake_storage_account_id. | `bool` | `false` | no |
| `data_lake_storage_account_id` | Storage account the factory identity is granted Storage Blob Data Contributor on. Required when assign_data_lake_role is true. | `string` | `null` | no |
| `create_data_lake_linked_service` | Create the ADLS Gen2 linked service (ls_datalake). | `bool` | `false` | no |
| `data_lake_dfs_endpoint` | DFS endpoint of the data lake (https://<account>.dfs.core.windows.net/). Required when create_data_lake_linked_service is true. | `string` | `null` | no |
| `create_databricks_linked_service` | Create the Databricks linked service (ls_databricks) authenticated with the factory managed identity. | `bool` | `false` | no |
| `databricks_workspace_url` | Databricks workspace host (https://adb-....azuredatabricks.net). Required when create_databricks_linked_service is true. | `string` | `null` | no |
| `databricks_workspace_id` | Azure resource ID of the Databricks workspace, used for managed-identity authentication from the linked service. | `string` | `null` | no |
| `databricks_cluster` | Job cluster shape used by the Databricks linked service. | `object(...)` | `{}` | no |
| `integration_runtime` | Managed-VNet Azure integration runtime settings. | `object(...)` | `{}` | no |
| `managed_private_endpoints` | Managed private endpoints created inside the factory's managed VNet, keyed by name. Each approval must still be completed on the target resource. | `map(...)` | `{}` | no |
| `git_configuration` | Optional Azure DevOps Git integration. Applies to the development factory only; other environments receive ARM templates from the pipeline. | `object(...)` | `null` | no |
| `enable_diagnostics` | Create the diagnostic setting. Kept separate from log_analytics_workspace_id so that the toggle is known at plan time even when the workspace is created in the same apply. | `bool` | `false` | no |
| `log_analytics_workspace_id` | Workspace ID for pipeline, activity and trigger run diagnostics. Required when enable_diagnostics is true. | `string` | `null` | no |
| `tags` | Tags applied to the factory. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Data Factory resource ID. |
| `name` | Data Factory name. |
| `principal_id` | Object ID of the factory's system-assigned identity. Grant this Storage Blob Data Contributor on the lake. |
| `integration_runtime_name` | Name of the managed-VNet integration runtime. |
| `linked_service_names` | Names of the linked services created, for use in pipeline parameters. |
