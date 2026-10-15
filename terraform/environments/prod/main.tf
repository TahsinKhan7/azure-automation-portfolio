# ------------------------------------------------------------------------------
# Data platform environment root.
#
# This file is byte-for-byte identical in every environment folder. All
# environment differences live in terraform.tfvars; the backend key lives in
# backend.tf. If you find yourself editing this file for one environment
# only, the change belongs in a variable instead.
#
# Module dependency order (also drawn in ../../README.md):
#   naming -> resource_group -> log_analytics -> networking
#          -> key_vault -> storage_account -> databricks_workspace
#          -> data_factory -> private_endpoints
#          -> databricks_cluster_policies / databricks_unity_catalog
# ------------------------------------------------------------------------------

locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    Platform    = "dataplatform"
    Workload    = var.workload
    CostCentre  = var.cost_centre
    ManagedBy   = "terraform"
  })

  # Zone IDs from a hub (var.private_dns_zone_ids) take precedence over any
  # zones this environment creates for itself. Membership is decided on the
  # map keys (known at plan time) rather than the IDs (unknown until apply).
  private_dns_zone_ids = merge(module.networking.private_dns_zone_ids, var.private_dns_zone_ids)
  zone                 = { for name in keys(local.private_dns_zone_ids) : name => [local.private_dns_zone_ids[name]] }

  private_endpoints = {
    vault = {
      resource_id          = module.key_vault.id
      subresource_names    = ["vault"]
      private_dns_zone_ids = lookup(local.zone, "privatelink.vaultcore.azure.net", [])
    }
    dfs = {
      resource_id          = module.storage_account.id
      subresource_names    = ["dfs"]
      private_dns_zone_ids = lookup(local.zone, "privatelink.dfs.core.windows.net", [])
    }
    blob = {
      resource_id          = module.storage_account.id
      subresource_names    = ["blob"]
      private_dns_zone_ids = lookup(local.zone, "privatelink.blob.core.windows.net", [])
    }
    adf = {
      resource_id          = module.data_factory.id
      subresource_names    = ["dataFactory"]
      private_dns_zone_ids = lookup(local.zone, "privatelink.datafactory.azure.net", [])
    }
    dbw-ui = {
      resource_id          = module.databricks_workspace.id
      subresource_names    = ["databricks_ui_api"]
      private_dns_zone_ids = lookup(local.zone, "privatelink.azuredatabricks.net", [])
    }
    dbw-auth = {
      resource_id          = module.databricks_workspace.id
      subresource_names    = ["browser_authentication"]
      private_dns_zone_ids = lookup(local.zone, "privatelink.azuredatabricks.net", [])
    }
  }
}

module "naming" {
  source = "../../modules/naming"

  prefix      = var.prefix
  workload    = var.workload
  environment = var.environment
  location    = var.location
  instance    = var.instance
}

module "resource_group" {
  source = "../../modules/resource-group"

  name                  = module.naming.resource_group
  location              = var.location
  lock_level            = var.resource_lock_level
  budget_amount         = var.budget_amount
  budget_start_date     = var.budget_start_date
  budget_contact_emails = var.budget_contact_emails
  tags                  = local.common_tags
}

module "log_analytics" {
  source = "../../modules/log-analytics"

  name                = module.naming.log_analytics_workspace
  resource_group_name = module.resource_group.name
  location            = var.location
  retention_in_days   = var.log_retention_in_days
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = local.common_tags
}

module "networking" {
  source = "../../modules/networking"

  vnet_name           = module.naming.virtual_network
  nsg_name            = module.naming.network_security_group
  resource_group_name = module.resource_group.name
  location            = var.location

  address_space                  = var.address_space
  databricks_public_subnet_cidr  = var.subnet_cidrs.databricks_public
  databricks_private_subnet_cidr = var.subnet_cidrs.databricks_private
  private_endpoint_subnet_cidr   = var.subnet_cidrs.private_endpoints

  enable_nat_gateway = var.enable_nat_gateway
  nat_gateway_name   = module.naming.nat_gateway
  nat_public_ip_name = module.naming.public_ip
  private_dns_zones  = var.private_dns_zones_to_create

  tags = local.common_tags
}

module "key_vault" {
  source = "../../modules/key-vault"

  name                = module.naming.key_vault
  resource_group_name = module.resource_group.name
  location            = var.location
  sku_name            = var.key_vault_sku

  purge_protection_enabled      = var.key_vault_purge_protection_enabled
  public_network_access_enabled = !var.enable_private_endpoints
  allowed_ip_ranges             = var.allowed_ip_ranges
  allowed_subnet_ids = [
    module.networking.databricks_public_subnet_id,
    module.networking.databricks_private_subnet_id,
  ]

  administrator_object_ids = var.platform_admin_object_ids
  secrets_user_object_ids  = var.secrets_reader_object_ids

  enable_diagnostics         = true
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.common_tags
}

module "storage_account" {
  source = "../../modules/storage-account"

  name                = module.naming.storage_account
  resource_group_name = module.resource_group.name
  location            = var.location

  replication_type           = var.storage_replication_type
  containers                 = var.storage_containers
  blob_soft_delete_days      = var.storage_soft_delete_days
  container_soft_delete_days = var.storage_soft_delete_days
  lifecycle_rules            = var.storage_lifecycle_rules

  public_network_access_enabled = !var.enable_private_endpoints
  allowed_ip_ranges             = var.allowed_ip_ranges
  allowed_subnet_ids = [
    module.networking.databricks_public_subnet_id,
    module.networking.databricks_private_subnet_id,
  ]

  blob_data_contributor_principal_ids = var.lake_contributor_object_ids
  blob_data_reader_principal_ids      = var.lake_reader_object_ids

  enable_diagnostics         = true
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.common_tags
}

module "databricks_workspace" {
  source = "../../modules/databricks-workspace"

  name                        = module.naming.databricks_workspace
  resource_group_name         = module.resource_group.name
  location                    = var.location
  sku                         = var.databricks_sku
  managed_resource_group_name = module.naming.databricks_managed_resource_group

  vnet_id                           = module.networking.vnet_id
  public_subnet_name                = module.networking.databricks_public_subnet_name
  private_subnet_name               = module.networking.databricks_private_subnet_name
  public_subnet_nsg_association_id  = module.networking.databricks_public_subnet_nsg_association_id
  private_subnet_nsg_association_id = module.networking.databricks_private_subnet_nsg_association_id

  no_public_ip                  = var.databricks_no_public_ip
  public_network_access_enabled = var.databricks_public_network_access_enabled

  access_connector_name = module.naming.databricks_access_connector
  assign_storage_role   = true
  storage_account_id    = module.storage_account.id

  enable_diagnostics         = true
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.common_tags
}

module "data_factory" {
  source = "../../modules/data-factory"

  name                = module.naming.data_factory
  resource_group_name = module.resource_group.name
  location            = var.location
  environment         = var.environment

  public_network_enabled = !var.enable_private_endpoints
  key_vault_id           = module.key_vault.id

  assign_data_lake_role        = true
  data_lake_storage_account_id = module.storage_account.id

  create_data_lake_linked_service = true
  data_lake_dfs_endpoint          = module.storage_account.primary_dfs_endpoint

  create_databricks_linked_service = true
  databricks_workspace_url         = module.databricks_workspace.workspace_url
  databricks_workspace_id          = module.databricks_workspace.id
  databricks_cluster               = var.data_factory_databricks_cluster

  git_configuration = var.data_factory_git_configuration

  managed_private_endpoints = {
    keyvault = {
      target_resource_id = module.key_vault.id
      subresource_name   = "vault"
    }
    datalake = {
      target_resource_id = module.storage_account.id
      subresource_name   = "dfs"
    }
  }

  enable_diagnostics         = true
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.common_tags
}

module "private_endpoints" {
  source = "../../modules/private-endpoints"
  count  = var.enable_private_endpoints ? 1 : 0

  name_prefix         = module.naming.private_endpoint_prefix
  subnet_id           = module.networking.private_endpoint_subnet_id
  resource_group_name = module.resource_group.name
  location            = var.location
  endpoints           = local.private_endpoints
  tags                = local.common_tags
}

module "databricks_cluster_policies" {
  source = "../../modules/databricks-cluster-policies"

  environment        = var.environment
  cost_centre        = var.cost_centre
  instance_pool_name = module.naming.databricks_instance_pool

  pool_node_type_id       = var.databricks_pool.node_type_id
  pool_max_capacity       = var.databricks_pool.max_capacity
  pool_min_idle_instances = var.databricks_pool.min_idle_instances
  pool_availability       = var.databricks_pool.availability

  max_workers                         = var.databricks_max_workers
  interactive_autotermination_minutes = var.databricks_interactive_autotermination_minutes
  policy_users                        = var.databricks_policy_users

  depends_on = [module.databricks_workspace]
}

module "unity_catalog" {
  source = "../../modules/databricks-unity-catalog"

  catalog_name = module.naming.unity_catalog
  environment  = var.environment

  workspace_id        = tonumber(module.databricks_workspace.workspace_id)
  metastore_id        = var.unity_catalog_metastore_id
  access_connector_id = module.databricks_workspace.access_connector_id

  storage_account_name      = module.storage_account.name
  schemas                   = var.unity_catalog_schemas
  catalog_storage_container = var.unity_catalog_storage_container

  catalog_owner   = var.unity_catalog_owner_group
  catalog_grants  = var.unity_catalog_grants
  schema_grants   = var.unity_catalog_schema_grants
  skip_validation = var.unity_catalog_skip_validation

  depends_on = [module.databricks_workspace, module.storage_account]
}
