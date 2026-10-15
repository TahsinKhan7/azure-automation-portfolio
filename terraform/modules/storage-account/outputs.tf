output "id" {
  description = "Storage account resource ID."
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "Storage account name."
  value       = azurerm_storage_account.this.name
}

output "primary_dfs_endpoint" {
  description = "ADLS Gen2 (DFS) endpoint."
  value       = azurerm_storage_account.this.primary_dfs_endpoint
}

output "primary_blob_endpoint" {
  description = "Blob endpoint."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "principal_id" {
  description = "Object ID of the account's system-assigned identity."
  value       = azurerm_storage_account.this.identity[0].principal_id
}

output "container_names" {
  description = "Names of the containers created."
  value       = [for c in azurerm_storage_container.this : c.name]
}

output "abfss_urls" {
  description = "Map of container name to abfss:// URL, ready for Unity Catalog external locations."
  value = {
    for c in azurerm_storage_container.this :
    c.name => "abfss://${c.name}@${azurerm_storage_account.this.name}.dfs.core.windows.net/"
  }
}
