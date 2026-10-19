# ------------------------------------------------------------------------------
# Azure Data Factory with a managed virtual network, system-assigned identity,
# Key Vault / ADLS / Databricks linked services and optional Git integration.
#
# Only the dev factory is Git-connected; every other environment is deployed
# from the ARM template published by the CI pipeline, so linked services
# here are created with the same names the pipeline parameters expect.
# ------------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "azurerm_data_factory" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  managed_virtual_network_enabled = true
  public_network_enabled          = var.public_network_enabled

  identity {
    type = "SystemAssigned"
  }

  global_parameter {
    name  = "env"
    type  = "String"
    value = var.environment
  }

  dynamic "vsts_configuration" {
    for_each = var.git_configuration != null ? [var.git_configuration] : []

    content {
      account_name    = vsts_configuration.value.account_name
      project_name    = vsts_configuration.value.project_name
      repository_name = vsts_configuration.value.repository_name
      branch_name     = vsts_configuration.value.branch_name
      root_folder     = vsts_configuration.value.root_folder
      tenant_id       = coalesce(vsts_configuration.value.tenant_id, data.azurerm_client_config.current.tenant_id)
    }
  }

  tags = var.tags
}

resource "azurerm_data_factory_integration_runtime_azure" "managed_vnet" {
  name                    = "ir-managed-vnet"
  data_factory_id         = azurerm_data_factory.this.id
  location                = var.location
  virtual_network_enabled = true
  compute_type            = var.integration_runtime.compute_type
  core_count              = var.integration_runtime.core_count
  time_to_live_min        = var.integration_runtime.time_to_live_min
}

# ---- Identity and access ----------------------------------------------------------

resource "azurerm_role_assignment" "key_vault_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_data_factory.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "data_lake_contributor" {
  count = var.assign_data_lake_role ? 1 : 0

  scope                = var.data_lake_storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.this.identity[0].principal_id

  lifecycle {
    precondition {
      condition     = var.data_lake_storage_account_id != null
      error_message = "data_lake_storage_account_id must be set when assign_data_lake_role is true."
    }
  }
}

# ---- Linked services ----------------------------------------------------------------

resource "azurerm_data_factory_linked_service_key_vault" "this" {
  name                     = "ls_keyvault"
  data_factory_id          = azurerm_data_factory.this.id
  key_vault_id             = var.key_vault_id
  integration_runtime_name = azurerm_data_factory_integration_runtime_azure.managed_vnet.name
  description              = "Connection secrets for downstream linked services."
}

resource "azurerm_data_factory_linked_service_data_lake_storage_gen2" "this" {
  count = var.create_data_lake_linked_service ? 1 : 0

  name                     = "ls_datalake"
  data_factory_id          = azurerm_data_factory.this.id
  url                      = var.data_lake_dfs_endpoint
  use_managed_identity     = true
  integration_runtime_name = azurerm_data_factory_integration_runtime_azure.managed_vnet.name
  description              = "Lakehouse storage accessed with the factory managed identity."

  lifecycle {
    precondition {
      condition     = var.data_lake_dfs_endpoint != null
      error_message = "data_lake_dfs_endpoint must be set when create_data_lake_linked_service is true."
    }
  }
}

resource "azurerm_data_factory_linked_service_azure_databricks" "this" {
  count = var.create_databricks_linked_service ? 1 : 0

  name                       = "ls_databricks"
  data_factory_id            = azurerm_data_factory.this.id
  adb_domain                 = var.databricks_workspace_url
  msi_work_space_resource_id = var.databricks_workspace_id
  integration_runtime_name   = azurerm_data_factory_integration_runtime_azure.managed_vnet.name
  description                = "Job clusters created per activity run using the factory managed identity."

  new_cluster_config {
    node_type             = var.databricks_cluster.node_type
    cluster_version       = var.databricks_cluster.cluster_version
    min_number_of_workers = var.databricks_cluster.min_workers
    max_number_of_workers = var.databricks_cluster.max_workers

    custom_tags = {
      Orchestrator = "adf"
      Environment  = var.environment
    }
  }

  lifecycle {
    precondition {
      condition     = var.databricks_workspace_url != null && var.databricks_workspace_id != null
      error_message = "databricks_workspace_url and databricks_workspace_id must be set when create_databricks_linked_service is true."
    }
  }
}

# ---- Managed private endpoints ----------------------------------------------------

resource "azurerm_data_factory_managed_private_endpoint" "this" {
  for_each = var.managed_private_endpoints

  name               = each.key
  data_factory_id    = azurerm_data_factory.this.id
  target_resource_id = each.value.target_resource_id
  subresource_name   = each.value.subresource_name

  depends_on = [azurerm_data_factory_integration_runtime_azure.managed_vnet]
}

# ---- Diagnostics ----------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.enable_diagnostics ? 1 : 0

  name                           = "diag-${var.name}"
  target_resource_id             = azurerm_data_factory.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "PipelineRuns"
  }

  enabled_log {
    category = "ActivityRuns"
  }

  enabled_log {
    category = "TriggerRuns"
  }

  metric {
    category = "AllMetrics"
  }

  lifecycle {
    precondition {
      condition     = var.log_analytics_workspace_id != null
      error_message = "log_analytics_workspace_id must be set when enable_diagnostics is true."
    }
  }
}
