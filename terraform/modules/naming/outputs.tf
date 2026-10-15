output "names" {
  description = "Map of every generated name keyed by resource type."
  value       = local.names
}

output "location_short" {
  description = "Short code for the region, as embedded in resource names."
  value       = local.location_short
}

output "resource_group" {
  description = "Resource group name."
  value       = local.names.resource_group
}

output "virtual_network" {
  description = "Virtual network name."
  value       = local.names.virtual_network
}

output "network_security_group" {
  description = "Network security group name."
  value       = local.names.network_security_group
}

output "log_analytics_workspace" {
  description = "Log Analytics workspace name."
  value       = local.names.log_analytics_workspace
}

output "key_vault" {
  description = "Key Vault name (validated to be 24 characters or fewer)."
  value       = local.names.key_vault

  precondition {
    condition     = length(local.names.key_vault) >= 3 && length(local.names.key_vault) <= 24
    error_message = "Generated Key Vault name '${local.names.key_vault}' must be between 3 and 24 characters. Shorten prefix or workload."
  }
}

output "storage_account" {
  description = "Storage account name (validated to be 3-24 lowercase alphanumerics)."
  value       = local.names.storage_account

  precondition {
    condition     = can(regex("^[a-z0-9]{3,24}$", local.names.storage_account))
    error_message = "Generated storage account name '${local.names.storage_account}' must be 3-24 lowercase alphanumerics. Shorten prefix or workload."
  }
}

output "data_factory" {
  description = "Data Factory name."
  value       = local.names.data_factory
}

output "databricks_workspace" {
  description = "Databricks workspace name."
  value       = local.names.databricks_workspace
}

output "databricks_managed_resource_group" {
  description = "Name of the Databricks managed resource group."
  value       = local.names.databricks_managed_resource_group
}

output "databricks_access_connector" {
  description = "Databricks access connector name."
  value       = local.names.databricks_access_connector
}

output "databricks_instance_pool" {
  description = "Shared Databricks instance pool name."
  value       = local.names.databricks_instance_pool
}

output "unity_catalog" {
  description = "Unity Catalog catalog name (underscore separated)."
  value       = local.names.unity_catalog
}

output "budget" {
  description = "Consumption budget name."
  value       = local.names.budget
}

output "private_endpoint_prefix" {
  description = "Prefix for private endpoint names; the private-endpoints module appends the endpoint key."
  value       = local.names.private_endpoint_prefix
}

output "nat_gateway" {
  description = "NAT gateway name."
  value       = local.names.nat_gateway
}

output "public_ip" {
  description = "Public IP name (used by the NAT gateway)."
  value       = local.names.public_ip
}
