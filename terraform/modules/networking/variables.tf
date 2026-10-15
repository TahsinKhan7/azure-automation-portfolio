variable "vnet_name" {
  description = "Virtual network name."
  type        = string
}

variable "nsg_name" {
  description = "Name of the network security group attached to the Databricks subnets."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for all networking resources."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "uksouth"
}

variable "address_space" {
  description = "Address space of the virtual network."
  type        = list(string)
  default     = ["10.0.0.0/16"]

  validation {
    condition     = alltrue([for cidr in var.address_space : can(cidrhost(cidr, 0))])
    error_message = "Every entry in address_space must be a valid CIDR block."
  }
}

variable "databricks_public_subnet_cidr" {
  description = "CIDR of the Databricks host (public) subnet."
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.databricks_public_subnet_cidr, 0))
    error_message = "databricks_public_subnet_cidr must be a valid CIDR block."
  }
}

variable "databricks_private_subnet_cidr" {
  description = "CIDR of the Databricks container (private) subnet."
  type        = string
  default     = "10.0.2.0/24"

  validation {
    condition     = can(cidrhost(var.databricks_private_subnet_cidr, 0))
    error_message = "databricks_private_subnet_cidr must be a valid CIDR block."
  }
}

variable "private_endpoint_subnet_cidr" {
  description = "CIDR of the subnet hosting private endpoints."
  type        = string
  default     = "10.0.3.0/24"

  validation {
    condition     = can(cidrhost(var.private_endpoint_subnet_cidr, 0))
    error_message = "private_endpoint_subnet_cidr must be a valid CIDR block."
  }
}

variable "service_endpoints" {
  description = "Service endpoints enabled on the Databricks subnets. Lets storage and Key Vault firewalls allow the subnets without private endpoints."
  type        = list(string)
  default     = ["Microsoft.Storage", "Microsoft.KeyVault"]
}

variable "enable_nat_gateway" {
  description = "Create a NAT gateway for Databricks egress. Required for secure cluster connectivity (no public IP) when no firewall provides outbound access."
  type        = bool
  default     = false
}

variable "nat_gateway_name" {
  description = "NAT gateway name. Required when enable_nat_gateway is true."
  type        = string
  default     = null
}

variable "nat_public_ip_name" {
  description = "Public IP name for the NAT gateway. Required when enable_nat_gateway is true."
  type        = string
  default     = null
}

variable "private_dns_zones" {
  description = "Private DNS zones to create and link to this VNet, for example privatelink.dfs.core.windows.net. In a hub-and-spoke estate these normally live in the hub; leave empty and pass hub zone IDs to the private-endpoints module instead."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all networking resources."
  type        = map(string)
  default     = {}
}
