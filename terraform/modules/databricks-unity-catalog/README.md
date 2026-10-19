# databricks-unity-catalog

**What this demonstrates:** the Unity Catalog layout for one environment: metastore assignment, a managed-identity storage credential, external locations per medallion container, an isolated catalog bound to the workspace, bronze/silver/gold schemas and authoritative group grants.

## Structure

| File | Purpose |
|------|---------|
| `main.tf` | Assignment, credential, external locations, catalog, binding, schemas and grants |
| `variables.tf` | Catalog and schema name regexes, grant maps per securable, isolation mode, owner |
| `outputs.tf` | Catalog, qualified schema names, credential and external location URLs |
| `versions.tf` | Terraform and provider version constraints |

## Usage

```hcl
module "unity_catalog" {
  source               = "../../modules/databricks-unity-catalog"
  catalog_name         = module.naming.unity_catalog
  environment          = var.environment
  workspace_id         = tonumber(module.databricks_workspace.workspace_id)
  access_connector_id  = module.databricks_workspace.access_connector_id
  storage_account_name = module.storage_account.name

  catalog_grants = {
    data-engineers = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY", "CREATE_TABLE"]
    data-analysts  = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
  }
  schema_grants = {
    gold = { business-reporting = ["USE_SCHEMA", "SELECT"] }
  }
}
```

Validate on its own with `terraform -chdir=terraform/modules/databricks-unity-catalog init -backend=false && terraform -chdir=terraform/modules/databricks-unity-catalog validate`.

## Design decisions

- One catalog per environment, `ISOLATED` and bound to its workspace, so a dev workspace can never see prod data even on a shared metastore.
- Storage access goes through a single credential backed by the access connector identity; no keys and no service principals.
- `databricks_grants` is authoritative per securable: privileges granted by hand in the UI are removed on the next apply, which is the behaviour a governed platform wants.
- Each schema has its own external location and storage root so data for each layer stays in its own container and lifecycle rules apply cleanly.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `catalog_name` | Catalog name (letters, digits and underscores). | `string` | n/a | yes |
| `environment` | Environment name, recorded as a catalog property and in comments. | `string` | n/a | yes |
| `workspace_id` | Numeric Databricks workspace ID, used for metastore assignment and the catalog workspace binding. | `number` | n/a | yes |
| `metastore_id` | ID of the regional Unity Catalog metastore to assign to the workspace. null assumes the assignment already exists (for example through account-level automation). | `string` | `null` | no |
| `access_connector_id` | Resource ID of the Databricks access connector used by the storage credential. | `string` | n/a | yes |
| `storage_account_name` | ADLS Gen2 account hosting the lake containers. | `string` | n/a | yes |
| `schemas` | Schemas to create in the catalog. Each schema also gets an external location pointing at the container of the same name. | `list(string)` | `[bronze, silver, gold]` | no |
| `catalog_storage_container` | Container used as the catalog's managed storage root. null uses the metastore default location. | `string` | `null` | no |
| `isolation_mode` | ISOLATED binds the catalog to this workspace only; OPEN makes it visible to every workspace on the metastore. | `string` | `ISOLATED` | no |
| `catalog_owner` | Account group that owns the catalog, schemas and external locations. null leaves the deploying principal as owner. | `string` | `null` | no |
| `catalog_grants` | Privileges granted on the catalog, keyed by account group name. | `map(list(string))` | `{data-engineers: [USE_CATALOG, USE_SCHEMA, SELECT, MODIFY...` | no |
| `schema_grants` | Additional privileges per schema, keyed by schema name then group name. Use this to tighten or widen access to individual layers (for example analysts on gold only). | `map(map(list(string)))` | `{}` | no |
| `external_location_grants` | Privileges granted on every external location, keyed by account group name. | `map(list(string))` | `{data-engineers: [READ_FILES, WRITE_FILES]}` | no |
| `skip_validation` | Skip connectivity validation when creating external locations. Only set true when the deploying principal cannot reach storage (for example during initial bootstrap). | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| `catalog_name` | Name of the catalog. |
| `schema_names` | Fully qualified schema names (catalog.schema). |
| `storage_credential_name` | Name of the storage credential. |
| `external_location_urls` | Map of external location name to abfss:// URL. |
