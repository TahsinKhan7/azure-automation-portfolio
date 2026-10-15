# iqe (integration quality / UAT): representative data volumes, so zone-redundant
# storage and a larger pool, still on public endpoints behind firewall rules.
environment = "iqe"
location    = "uksouth"
cost_centre = "CC-DATA-TEST"

tags = {
  Owner = "data-platform-team"
  Tier  = "non-production"
}

# Governance
resource_lock_level   = null
budget_amount         = 1000
budget_contact_emails = ["dataplatform-alerts@example.com"]

# Observability
log_retention_in_days = 30
log_daily_quota_gb    = 5

# Networking
address_space = ["10.12.0.0/16"]
subnet_cidrs = {
  databricks_public  = "10.12.1.0/24"
  databricks_private = "10.12.2.0/24"
  private_endpoints  = "10.12.3.0/24"
}
enable_nat_gateway       = false
enable_private_endpoints = false
allowed_ip_ranges        = ["203.0.113.10", "198.51.100.0/24"]

# Identity
platform_admin_object_ids = ["00000000-0000-0000-0000-000000000000"]
secrets_reader_object_ids = ["00000000-0000-0000-0000-000000000001"]

# Key Vault
key_vault_sku                      = "standard"
key_vault_purge_protection_enabled = true

# Storage
storage_replication_type = "ZRS"
storage_soft_delete_days = 14
storage_lifecycle_rules = {
  bronze = {
    prefix_match         = ["bronze/"]
    tier_to_cool_days    = 60
    tier_to_archive_days = 180
  }
}

# Databricks
databricks_no_public_ip                  = true
databricks_public_network_access_enabled = true
databricks_pool = {
  node_type_id       = "Standard_DS3_v2"
  max_capacity       = 16
  min_idle_instances = 0
  availability       = "SPOT_AZURE"
}
databricks_max_workers                         = 8
databricks_interactive_autotermination_minutes = 45

# Data Factory
data_factory_git_configuration = null

# Unity Catalog
unity_catalog_owner_group = "data-platform-admins"
unity_catalog_grants = {
  data-engineers = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY", "CREATE_TABLE", "CREATE_SCHEMA"]
  data-analysts  = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
}
unity_catalog_schema_grants = {
  gold = {
    business-reporting = ["USE_SCHEMA", "SELECT"]
  }
}
