output "vnet_id" {
  description = "Virtual network resource ID."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Virtual network name."
  value       = azurerm_virtual_network.this.name
}

output "databricks_public_subnet_name" {
  description = "Name of the Databricks host subnet."
  value       = azurerm_subnet.databricks_public.name
}

output "databricks_private_subnet_name" {
  description = "Name of the Databricks container subnet."
  value       = azurerm_subnet.databricks_private.name
}

output "databricks_public_subnet_id" {
  description = "ID of the Databricks host subnet."
  value       = azurerm_subnet.databricks_public.id
}

output "databricks_private_subnet_id" {
  description = "ID of the Databricks container subnet."
  value       = azurerm_subnet.databricks_private.id
}

output "databricks_public_subnet_nsg_association_id" {
  description = "NSG association ID for the host subnet (required by the Databricks workspace)."
  value       = azurerm_subnet_network_security_group_association.public.id
}

output "databricks_private_subnet_nsg_association_id" {
  description = "NSG association ID for the container subnet (required by the Databricks workspace)."
  value       = azurerm_subnet_network_security_group_association.private.id
}

output "private_endpoint_subnet_id" {
  description = "ID of the private endpoint subnet."
  value       = azurerm_subnet.private_endpoints.id
}

output "nsg_id" {
  description = "ID of the Databricks network security group."
  value       = azurerm_network_security_group.databricks.id
}

output "nat_gateway_public_ip" {
  description = "Egress IP of the NAT gateway, or null when not enabled. Allow-list this on downstream firewalls."
  value       = try(azurerm_public_ip.nat[0].ip_address, null)
}

output "private_dns_zone_ids" {
  description = "Map of private DNS zone name to zone ID for zones created by this module."
  value       = { for k, v in azurerm_private_dns_zone.this : k => v.id }
}
