# ------------------------------------------------------------------------------
# VNet-injected Azure Databricks workspace plus a Unity Catalog access connector.
#
# The access connector is created here (azurerm) rather than in the
# unity-catalog module (databricks provider) so that the storage role
# assignment exists before any Databricks API call is attempted.
# ------------------------------------------------------------------------------

resource "azurerm_databricks_workspace" "this" {
  name                        = var.name
  resource_group_name         = var.resource_group_name
  location                    = var.location
  sku                         = var.sku
  managed_resource_group_name = var.managed_resource_group_name

  public_network_access_enabled         = var.public_network_access_enabled
  network_security_group_rules_required = var.public_network_access_enabled ? "AllRules" : "NoAzureDatabricksRules"

  custom_parameters {
    no_public_ip                                         = var.no_public_ip
    virtual_network_id                                   = var.vnet_id
    public_subnet_name                                   = var.public_subnet_name
    private_subnet_name                                  = var.private_subnet_name
    public_subnet_network_security_group_association_id  = var.public_subnet_nsg_association_id
    private_subnet_network_security_group_association_id = var.private_subnet_nsg_association_id
    storage_account_sku_name                             = "Standard_ZRS"
  }

  tags = var.tags
}

resource "azurerm_databricks_access_connector" "this" {
  name                = var.access_connector_name
  resource_group_name = var.resource_group_name
  location            = var.location

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "azurerm_role_assignment" "access_connector_storage" {
  count = var.assign_storage_role ? 1 : 0

  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.this.identity[0].principal_id

  lifecycle {
    precondition {
      condition     = var.storage_account_id != null
      error_message = "storage_account_id must be set when assign_storage_role is true."
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_databricks_workspace.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Databricks exposes no metrics; only the log category group is configured.
  enabled_log {
    category_group = "allLogs"
  }

  lifecycle {
    precondition {
      condition     = var.log_analytics_workspace_id != null
      error_message = "log_analytics_workspace_id must be set when enable_diagnostics is true."
    }
  }
}
