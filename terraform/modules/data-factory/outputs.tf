output "id" {
  description = "Data Factory resource ID."
  value       = azurerm_data_factory.this.id
}

output "name" {
  description = "Data Factory name."
  value       = azurerm_data_factory.this.name
}

output "principal_id" {
  description = "Object ID of the factory's system-assigned identity. Grant this Storage Blob Data Contributor on the lake."
  value       = azurerm_data_factory.this.identity[0].principal_id
}

output "integration_runtime_name" {
  description = "Name of the managed-VNet integration runtime."
  value       = azurerm_data_factory_integration_runtime_azure.managed_vnet.name
}

output "linked_service_names" {
  description = "Names of the linked services created, for use in pipeline parameters."
  value = compact([
    azurerm_data_factory_linked_service_key_vault.this.name,
    try(azurerm_data_factory_linked_service_data_lake_storage_gen2.this[0].name, ""),
    try(azurerm_data_factory_linked_service_azure_databricks.this[0].name, ""),
  ])
}
