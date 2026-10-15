# ------------------------------------------------------------------------------
# Unity Catalog layout for one environment.
#
#   metastore ──(assignment)── workspace
#        │
#        └── catalog  <env catalog, ISOLATED to the workspace>
#              ├── bronze  ──► external location abfss://bronze@...
#              ├── silver  ──► external location abfss://silver@...
#              └── gold    ──► external location abfss://gold@...
#
# Storage access is through a single storage credential backed by the
# access connector's managed identity; no keys or service principals.
# Grants are declared per group and are authoritative (databricks_grants).
# ------------------------------------------------------------------------------

locals {
  dfs_host = "${var.storage_account_name}.dfs.core.windows.net"

  external_location_containers = distinct(concat(
    var.schemas,
    var.catalog_storage_container != null ? [var.catalog_storage_container] : [],
  ))

  abfss_urls = {
    for c in local.external_location_containers :
    c => "abfss://${c}@${local.dfs_host}/"
  }

  schema_grant_pairs = flatten([
    for schema, grants in var.schema_grants : [
      for principal, privileges in grants : {
        schema     = schema
        principal  = principal
        privileges = privileges
      }
    ]
  ])
}

resource "databricks_metastore_assignment" "this" {
  count = var.metastore_id != null ? 1 : 0

  metastore_id = var.metastore_id
  workspace_id = var.workspace_id
}

resource "databricks_storage_credential" "lake" {
  name    = "sc-${var.catalog_name}"
  comment = "Managed identity of the ${var.environment} access connector."

  azure_managed_identity {
    access_connector_id = var.access_connector_id
  }

  depends_on = [databricks_metastore_assignment.this]
}

resource "databricks_external_location" "this" {
  for_each = local.abfss_urls

  name            = "el-${var.catalog_name}-${each.key}"
  url             = each.value
  credential_name = databricks_storage_credential.lake.name
  comment         = "${each.key} container for ${var.catalog_name}."
  skip_validation = var.skip_validation
}

resource "databricks_grants" "external_locations" {
  for_each = length(var.external_location_grants) > 0 ? databricks_external_location.this : {}

  external_location = each.value.id

  dynamic "grant" {
    for_each = var.external_location_grants

    content {
      principal  = grant.key
      privileges = grant.value
    }
  }
}

resource "databricks_catalog" "this" {
  name           = var.catalog_name
  comment        = "${var.environment} lakehouse catalog."
  owner          = var.catalog_owner
  isolation_mode = var.isolation_mode
  storage_root   = var.catalog_storage_container != null ? local.abfss_urls[var.catalog_storage_container] : null

  properties = {
    environment = var.environment
    managed_by  = "terraform"
  }

  depends_on = [databricks_external_location.this]
}

resource "databricks_workspace_binding" "this" {
  count = var.isolation_mode == "ISOLATED" ? 1 : 0

  securable_name = databricks_catalog.this.name
  securable_type = "catalog"
  workspace_id   = var.workspace_id
}

resource "databricks_grants" "catalog" {
  count = length(var.catalog_grants) > 0 ? 1 : 0

  catalog = databricks_catalog.this.name

  dynamic "grant" {
    for_each = var.catalog_grants

    content {
      principal  = grant.key
      privileges = grant.value
    }
  }
}

resource "databricks_schema" "this" {
  for_each = toset(var.schemas)

  catalog_name = databricks_catalog.this.name
  name         = each.value
  owner        = var.catalog_owner
  comment      = "${each.value} layer of the ${var.environment} medallion architecture."
  storage_root = local.abfss_urls[each.value]

  properties = {
    layer = each.value
  }

  depends_on = [databricks_external_location.this]
}

resource "databricks_grants" "schemas" {
  for_each = { for p in local.schema_grant_pairs : p.schema => p... }

  schema = databricks_schema.this[each.key].id

  dynamic "grant" {
    for_each = each.value

    content {
      principal  = grant.value.principal
      privileges = grant.value.privileges
    }
  }
}
