# ------------------------------------------------------------------------------
# Networking for a VNet-injected Databricks workspace plus private endpoints.
#
#  - Two delegated subnets (host/container) sharing one NSG. Databricks adds
#    its required rules automatically once the subnet association exists.
#  - A dedicated private endpoint subnet with network policies disabled.
#  - Optional NAT gateway for secure cluster connectivity egress.
#  - Optional private DNS zones for single-VNet (non-hub) estates.
# ------------------------------------------------------------------------------

locals {
  databricks_delegation_actions = [
    "Microsoft.Network/virtualNetworks/subnets/join/action",
    "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
    "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action",
  ]
}

resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.address_space
  tags                = var.tags
}

resource "azurerm_network_security_group" "databricks" {
  name                = var.nsg_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_subnet" "databricks_public" {
  name                 = "snet-dbw-host"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.databricks_public_subnet_cidr]
  service_endpoints    = var.service_endpoints

  delegation {
    name = "databricks"

    service_delegation {
      name    = "Microsoft.Databricks/workspaces"
      actions = local.databricks_delegation_actions
    }
  }
}

resource "azurerm_subnet" "databricks_private" {
  name                 = "snet-dbw-container"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.databricks_private_subnet_cidr]
  service_endpoints    = var.service_endpoints

  delegation {
    name = "databricks"

    service_delegation {
      name    = "Microsoft.Databricks/workspaces"
      actions = local.databricks_delegation_actions
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.private_endpoint_subnet_cidr]

  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.databricks_public.id
  network_security_group_id = azurerm_network_security_group.databricks.id
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.databricks_private.id
  network_security_group_id = azurerm_network_security_group.databricks.id
}

# ---- Optional NAT gateway for Databricks egress -------------------------------

resource "azurerm_public_ip" "nat" {
  count = var.enable_nat_gateway ? 1 : 0

  name                = coalesce(var.nat_public_ip_name, "pip-${var.vnet_name}-nat")
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  count = var.enable_nat_gateway ? 1 : 0

  name                    = coalesce(var.nat_gateway_name, "ng-${var.vnet_name}")
  resource_group_name     = var.resource_group_name
  location                = var.location
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  count = var.enable_nat_gateway ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.this[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "public" {
  count = var.enable_nat_gateway ? 1 : 0

  subnet_id      = azurerm_subnet.databricks_public.id
  nat_gateway_id = azurerm_nat_gateway.this[0].id
}

resource "azurerm_subnet_nat_gateway_association" "private" {
  count = var.enable_nat_gateway ? 1 : 0

  subnet_id      = azurerm_subnet.databricks_private.id
  nat_gateway_id = azurerm_nat_gateway.this[0].id
}

# ---- Optional private DNS zones -------------------------------------------------

resource "azurerm_private_dns_zone" "this" {
  for_each = toset(var.private_dns_zones)

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = azurerm_private_dns_zone.this

  name                  = "link-${var.vnet_name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}
