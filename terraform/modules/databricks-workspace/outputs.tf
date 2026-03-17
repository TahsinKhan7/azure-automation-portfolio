output "workspace_id"  { value = azurerm_databricks_workspace.this.id }
output "workspace_url" { value = azurerm_databricks_workspace.this.workspace_url }
output "managed_rg_id" { value = azurerm_databricks_workspace.this.managed_resource_group_id }
