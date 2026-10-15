# dev: lowest cost, fastest iteration. Public endpoints behind firewall rules,
# spot pools, short retention, purge protection off so the vault can be rebuilt.
environment = "dev"
location    = "uksouth"
cost_centre = "CC-DATA-DEV"

tags = {
  Owner = "data-platform-team"
  Tier  = "non-production"
}

# Governance
resource_lock_level   = null
budget_amount         = 500
budget_contact_emails = ["dataplatform-alerts@example.com"]

# Observability
log_retention_in_days = 30
log_daily_quota_gb    = 2

# Networking
address_space = ["10.10.0.0/16"]
subnet_cidrs = {
  databricks_public  = "10.10.1.0/24"
  databricks_private = "10.10.2.0/24"
  private_endpoints  = "10.10.3.0/24"
}
enable_nat_gateway       = false
enable_private_endpoints = false
allowed_ip_ranges        = ["203.0.113.10", "198.51.100.0/24"] # build agents, office egress (placeholders)

# Identity (placeholders: platform admins group, AKS workload identity)
platform_admin_object_ids = ["00000000-0000-0000-0000-000000000000"]
secrets_reader_object_ids = ["00000000-0000-0000-0000-000000000001"]

# Key Vault
key_vault_sku                      = "standard"
key_vault_purge_protection_enabled = false

# Storage
storage_replication_type = "LRS"
storage_soft_delete_days = 7
storage_lifecycle_rules = {
  bronze = {
    prefix_match      = ["bronze/"]
    tier_to_cool_days = 30
    delete_days       = 90
  }
}

# Databricks
databricks_no_public_ip                  = true
databricks_public_network_access_enabled = true
databricks_pool = {
  node_type_id       = "Standard_DS3_v2"
  max_capacity       = 8
  min_idle_instances = 0
  availability       = "SPOT_AZURE"
}
databricks_max_workers                         = 4
databricks_interactive_autotermination_minutes = 30

# Data Factory: only dev is Git-connected; other environments receive published ARM templates.
data_factory_git_configuration = {
  account_name    = "your-ado-organisation"
  project_name    = "dataplatform"
  repository_name = "dataplatform-adf"
  branch_name     = "main"
  root_folder     = "/adf"
}

# Unity Catalog
unity_catalog_owner_group = "data-platform-admins"
unity_catalog_grants = {
  data-engineers  = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY", "CREATE_TABLE", "CREATE_SCHEMA"]
  data-analysts   = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
  data-scientists = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "CREATE_TABLE"]
}
