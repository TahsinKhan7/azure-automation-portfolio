# prod: geo-zone-redundant storage, private connectivity only (workspace UI
# reachable through private endpoints), warm on-demand pool, 1-year logs,
# delete lock and the strictest grants. Engineers have no MODIFY on prod data.
environment = "prod"
location    = "uksouth"
cost_centre = "CC-DATA-PROD"

tags = {
  Owner       = "data-platform-team"
  Tier        = "production"
  Criticality = "high"
}

# Governance
resource_lock_level   = "CanNotDelete"
budget_amount         = 8000
budget_contact_emails = ["dataplatform-alerts@example.com", "finops@example.com"]

# Observability
log_retention_in_days = 365
log_daily_quota_gb    = -1

# Networking
address_space = ["10.14.0.0/16"]
subnet_cidrs = {
  databricks_public  = "10.14.1.0/24"
  databricks_private = "10.14.2.0/24"
  private_endpoints  = "10.14.3.0/24"
}
enable_nat_gateway       = true
enable_private_endpoints = true
allowed_ip_ranges        = ["203.0.113.10"] # self-hosted build agents only

private_dns_zones_to_create = [
  "privatelink.vaultcore.azure.net",
  "privatelink.dfs.core.windows.net",
  "privatelink.blob.core.windows.net",
  "privatelink.datafactory.azure.net",
  "privatelink.azuredatabricks.net",
]

# Identity
platform_admin_object_ids = ["00000000-0000-0000-0000-000000000000"]
secrets_reader_object_ids = ["00000000-0000-0000-0000-000000000001"]
lake_reader_object_ids = {
  business-reporting = "00000000-0000-0000-0000-000000000002"
}

# Key Vault
key_vault_sku                      = "premium"
key_vault_purge_protection_enabled = true

# Storage
storage_replication_type = "GZRS"
storage_soft_delete_days = 30
storage_lifecycle_rules = {
  bronze = {
    prefix_match         = ["bronze/"]
    tier_to_cool_days    = 90
    tier_to_archive_days = 365
  }
  silver = {
    prefix_match      = ["silver/"]
    tier_to_cool_days = 180
  }
}

# Databricks
databricks_no_public_ip                  = true
databricks_public_network_access_enabled = false
databricks_pool = {
  node_type_id       = "Standard_E8ds_v5"
  max_capacity       = 40
  min_idle_instances = 2
  availability       = "ON_DEMAND_AZURE"
}
databricks_max_workers                         = 16
databricks_interactive_autotermination_minutes = 60
databricks_policy_users = {
  job         = ["data-engineers"]
  shared      = ["data-analysts"]
  single_node = ["data-scientists"]
}

# Data Factory
data_factory_git_configuration = null
data_factory_databricks_cluster = {
  node_type   = "Standard_E8ds_v5"
  min_workers = 2
  max_workers = 8
}

# Unity Catalog
unity_catalog_owner_group = "data-platform-admins"
unity_catalog_grants = {
  data-engineers = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
  data-analysts  = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
}
unity_catalog_schema_grants = {
  gold = {
    business-reporting = ["USE_SCHEMA", "SELECT"]
  }
}
