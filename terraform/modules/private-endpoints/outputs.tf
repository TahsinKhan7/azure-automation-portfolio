output "ids" {
  description = "Map of endpoint key to private endpoint resource ID."
  value       = { for k, v in azurerm_private_endpoint.this : k => v.id }
}

output "private_ip_addresses" {
  description = "Map of endpoint key to the allocated private IP address."
  value       = { for k, v in azurerm_private_endpoint.this : k => v.private_service_connection[0].private_ip_address }
}
