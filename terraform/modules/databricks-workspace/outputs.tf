output "id" {
  description = "Workspace Azure resource ID (used for the databricks provider's azure_workspace_resource_id)."
  value       = azurerm_databricks_workspace.this.id
}

output "workspace_id" {
  description = "Numeric Databricks workspace ID (used for metastore assignment and workspace bindings)."
  value       = azurerm_databricks_workspace.this.workspace_id
}

output "workspace_url" {
  description = "Workspace host, for example https://adb-1234567890123456.7.azuredatabricks.net."
  value       = "https://${azurerm_databricks_workspace.this.workspace_url}"
}

output "managed_resource_group_id" {
  description = "ID of the Databricks managed resource group."
  value       = azurerm_databricks_workspace.this.managed_resource_group_id
}

output "access_connector_id" {
  description = "Access connector resource ID (used by the Unity Catalog storage credential)."
  value       = azurerm_databricks_access_connector.this.id
}

output "access_connector_principal_id" {
  description = "Object ID of the access connector's managed identity."
  value       = azurerm_databricks_access_connector.this.identity[0].principal_id
}
