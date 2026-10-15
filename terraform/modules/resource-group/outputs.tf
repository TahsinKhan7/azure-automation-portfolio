output "id" {
  description = "Resource group resource ID."
  value       = azurerm_resource_group.this.id
}

output "name" {
  description = "Resource group name."
  value       = azurerm_resource_group.this.name
}

output "location" {
  description = "Resource group location."
  value       = azurerm_resource_group.this.location
}

output "lock_id" {
  description = "Management lock ID, or null when no lock is configured."
  value       = try(azurerm_management_lock.this[0].id, null)
}

output "budget_id" {
  description = "Consumption budget ID, or null when no budget is configured."
  value       = try(azurerm_consumption_budget_resource_group.this[0].id, null)
}
