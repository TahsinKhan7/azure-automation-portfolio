# ------------------------------------------------------------------------------
# Log Analytics workspace plus a diagnostic-settings helper.
#
# Every other module can forward its own diagnostics by accepting the
# workspace ID, but for resources created outside this configuration
# (or for bulk onboarding) the diagnostic_targets map creates a uniform
# "all logs + all metrics" setting per resource ID.
# ------------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  retention_in_days   = var.retention_in_days
  daily_quota_gb      = var.daily_quota_gb

  internet_ingestion_enabled = var.internet_ingestion_enabled
  internet_query_enabled     = var.internet_query_enabled

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "targets" {
  for_each = var.diagnostic_targets

  name                       = "diag-${each.key}-to-law"
  target_resource_id         = each.value
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = var.diagnostic_log_category_group
  }

  metric {
    category = "AllMetrics"
  }
}
