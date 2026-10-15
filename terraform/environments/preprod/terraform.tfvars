# preprod: production shape at reduced scale. Private endpoints, NAT egress,
# delete lock, on-demand pool, 90-day logs. Used for release rehearsal and DR tests.
environment = "preprod"
location    = "uksouth"
cost_centre = "CC-DATA-PREPROD"

tags = {
  Owner = "data-platform-team"
  Tier  = "pre-production"
}

# Governance
resource_lock_level   = "CanNotDelete"
budget_amount         = 2500
budget_contact_emails = ["dataplatform-alerts@example.com", "finops@example.com"]

# Observability
log_retention_in_days = 90
log_daily_quota_gb    = -1

# Networking
address_space = ["10.13.0.0/16"]
subnet_cidrs = {
  databricks_public  = "10.13.1.0/24"
  databricks_private = "10.13.2.0/24"
  private_endpoints  = "10.13.3.0/24"
}
enable_nat_gateway       = true
enable_private_endpoints = true
allowed_ip_ranges        = ["203.0.113.10"] # self-hosted build agents only

# Private DNS zones are created locally here; in a hub-and-spoke estate pass
# private_dns_zone_ids instead and leave this list empty.
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
key_vault_sku                      = "standard"
key_vault_purge_protection_enabled = true

# Storage
storage_replication_type = "ZRS"
storage_soft_delete_days = 30
storage_lifecycle_rules = {
  bronze = {
    prefix_match         = ["bronze/"]
    tier_to_cool_days    = 90
    tier_to_archive_days = 365
  }
}

# Databricks
databricks_no_public_ip                  = true
databricks_public_network_access_enabled = true
databricks_pool = {
  node_type_id       = "Standard_E4ds_v5"
  max_capacity       = 24
  min_idle_instances = 1
  availability       = "ON_DEMAND_AZURE"
}
databricks_max_workers                         = 8
databricks_interactive_autotermination_minutes = 60

# Data Factory
data_factory_git_configuration = null
data_factory_databricks_cluster = {
  node_type   = "Standard_E4ds_v5"
  min_workers = 1
  max_workers = 4
}

# Unity Catalog
unity_catalog_owner_group = "data-platform-admins"
unity_catalog_grants = {
  data-engineers = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY", "CREATE_TABLE"]
  data-analysts  = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
}
unity_catalog_schema_grants = {
  gold = {
    business-reporting = ["USE_SCHEMA", "SELECT"]
  }
}
