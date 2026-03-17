terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = ">= 3.0" }
  }
}

resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.address_space
  tags                = merge(var.tags, { ManagedBy = "Terraform" })
}

resource "azurerm_subnet" "databricks_public" {
  name                 = "${var.vnet_name}-dbx-public"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.databricks_public_cidr]

  delegation {
    name = "databricks"
    service_delegation {
      name    = "Microsoft.Databricks/workspaces"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action",
                 "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
                 "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"]
    }
  }
}

resource "azurerm_subnet" "databricks_private" {
  name                 = "${var.vnet_name}-dbx-private"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.databricks_private_cidr]

  delegation {
    name = "databricks"
    service_delegation {
      name    = "Microsoft.Databricks/workspaces"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action",
                 "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
                 "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"]
    }
  }
}

resource "azurerm_network_security_group" "databricks" {
  name                = "${var.vnet_name}-dbx-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.databricks_public.id
  network_security_group_id = azurerm_network_security_group.databricks.id
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.databricks_private.id
  network_security_group_id = azurerm_network_security_group.databricks.id
}
