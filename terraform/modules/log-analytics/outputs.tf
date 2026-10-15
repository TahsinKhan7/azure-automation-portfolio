output "id" {
  description = "Workspace resource ID (used by diagnostic settings)."
  value       = azurerm_log_analytics_workspace.this.id
}

output "name" {
  description = "Workspace name."
  value       = azurerm_log_analytics_workspace.this.name
}

output "workspace_id" {
  description = "Workspace (customer) GUID used by agents and the Data Collector API."
  value       = azurerm_log_analytics_workspace.this.workspace_id
}

output "diagnostic_setting_ids" {
  description = "Map of diagnostic setting IDs created by the helper, keyed by target name."
  value       = { for k, v in azurerm_monitor_diagnostic_setting.targets : k => v.id }
}
