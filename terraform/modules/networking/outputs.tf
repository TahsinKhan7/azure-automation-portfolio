output "vnet_id"               { value = azurerm_virtual_network.this.id }
output "public_subnet_name"    { value = azurerm_subnet.databricks_public.name }
output "private_subnet_name"   { value = azurerm_subnet.databricks_private.name }
output "public_subnet_nsg_id"  { value = azurerm_subnet_network_security_group_association.public.id }
output "private_subnet_nsg_id" { value = azurerm_subnet_network_security_group_association.private.id }
