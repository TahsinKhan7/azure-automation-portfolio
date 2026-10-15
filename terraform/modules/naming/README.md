# naming

**What this demonstrates:** a provider-free module that computes every resource name from `{prefix, workload, environment, location, instance}`, enforces Azure character and length rules with `validation` and output `precondition` blocks, and keeps Terraform, Bicep and the Kubernetes overlays agreeing on names.

## Structure

| File | Purpose |
|------|---------|
| `main.tf` | Convention and the `names` map |
| `variables.tf` | Inputs with validation (environment list, prefix/workload regex, instance digits) |
| `outputs.tf` | One output per resource type plus the whole map; Key Vault and storage names carry length preconditions |
| `versions.tf` | Terraform and provider version constraints |

## Usage

```hcl
module "naming" {
  source      = "../../modules/naming"
  prefix      = "dp"
  workload    = "data"
  environment = "prod"
  location    = "uksouth"
}

# rg-dp-data-prod-uks-01, stdpdataprod01, kv-dp-data-prod-01, dp_data_prod
```

Validate on its own with `terraform -chdir=terraform/modules/naming init -backend=false && terraform -chdir=terraform/modules/naming validate`.

## Design decisions

- Names are data, not string templates scattered through modules. Changing the convention is a one-file change tested by `tests/naming.tftest.hcl`.
- Key Vault and storage names omit the location so `preprod` fits within 24 characters; the preconditions make the failure explicit rather than letting Azure reject the name mid-apply.
- Unknown regions fall back to the first three letters of the region name so the module never blocks a new region, while the map keeps the common ones readable.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `prefix` | Short organisation or platform prefix used at the start of every resource name (2-4 lowercase letters). | `string` | `dp` | no |
| `environment` | Deployment environment. One of: dev, ite, iqe, preprod, prod. | `string` | n/a | yes |
| `location` | Azure region the resources are deployed to. Must have an entry in location_short_codes. | `string` | `uksouth` | no |
| `workload` | Workload or application identifier (2-10 lowercase alphanumerics), for example data, ingest, api. | `string` | `data` | no |
| `instance` | Two-digit instance number used to disambiguate repeated deployments of the same workload. | `string` | `01` | no |
| `location_short_codes` | Map of Azure region name to the short code embedded in resource names. | `map(string)` | `{uksouth: uks, ukwest: ukw, northeurope: neu, westeurope:...` | no |

## Outputs

| Name | Description |
|------|-------------|
| `names` | Map of every generated name keyed by resource type. |
| `location_short` | Short code for the region, as embedded in resource names. |
| `resource_group` | Resource group name. |
| `virtual_network` | Virtual network name. |
| `network_security_group` | Network security group name. |
| `log_analytics_workspace` | Log Analytics workspace name. |
| `key_vault` | Key Vault name (validated to be 24 characters or fewer). |
| `storage_account` | Storage account name (validated to be 3-24 lowercase alphanumerics). |
| `data_factory` | Data Factory name. |
| `databricks_workspace` | Databricks workspace name. |
| `databricks_managed_resource_group` | Name of the Databricks managed resource group. |
| `databricks_access_connector` | Databricks access connector name. |
| `databricks_instance_pool` | Shared Databricks instance pool name. |
| `unity_catalog` | Unity Catalog catalog name (underscore separated). |
| `budget` | Consumption budget name. |
| `private_endpoint_prefix` | Prefix for private endpoint names; the private-endpoints module appends the endpoint key. |
| `nat_gateway` | NAT gateway name. |
| `public_ip` | Public IP name (used by the NAT gateway). |
