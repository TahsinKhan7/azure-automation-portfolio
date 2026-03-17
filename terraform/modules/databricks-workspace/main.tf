terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = ">= 3.0" }
  }
}

resource "azurerm_databricks_workspace" "this" {
  name                        = var.workspace_name
  resource_group_name         = var.resource_group_name
  location                    = var.location
  sku                         = var.sku
  managed_resource_group_name = "${var.workspace_name}-managed-rg"

  custom_parameters {
    no_public_ip                                         = var.no_public_ip
    virtual_network_id                                   = var.vnet_id
    public_subnet_name                                   = var.public_subnet_name
    private_subnet_name                                  = var.private_subnet_name
    public_subnet_network_security_group_association_id   = var.public_subnet_nsg_id
    private_subnet_network_security_group_association_id  = var.private_subnet_nsg_id
  }

  tags = merge(var.tags, { ManagedBy = "Terraform" })
}

resource "azurerm_monitor_diagnostic_setting" "databricks" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "${var.workspace_name}-diag"
  target_resource_id         = azurerm_databricks_workspace.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "accounts" }
  enabled_log { category = "clusters" }
  enabled_log { category = "jobs" }
}
