output "resource_group_name" {
  description = "Resource group containing the environment."
  value       = module.resource_group.name
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID."
  value       = module.log_analytics.id
}

output "key_vault_uri" {
  description = "Key Vault URI used by pipelines and the AKS Secrets Store CSI driver."
  value       = module.key_vault.vault_uri
}

output "storage_account_name" {
  description = "Lake storage account name."
  value       = module.storage_account.name
}

output "storage_dfs_endpoint" {
  description = "Lake DFS endpoint."
  value       = module.storage_account.primary_dfs_endpoint
}

output "databricks_workspace_url" {
  description = "Databricks workspace URL."
  value       = module.databricks_workspace.workspace_url
}

output "databricks_workspace_id" {
  description = "Numeric Databricks workspace ID."
  value       = module.databricks_workspace.workspace_id
}

output "data_factory_name" {
  description = "Data Factory name, consumed by the ADF deployment pipeline."
  value       = module.data_factory.name
}

output "data_factory_principal_id" {
  description = "Object ID of the Data Factory managed identity."
  value       = module.data_factory.principal_id
}

output "unity_catalog_name" {
  description = "Environment catalog name."
  value       = module.unity_catalog.catalog_name
}

output "cluster_policy_ids" {
  description = "Cluster policy IDs keyed by policy (job, shared, single_node)."
  value       = module.databricks_cluster_policies.policy_ids
}

output "nat_gateway_public_ip" {
  description = "Databricks egress IP when the NAT gateway is enabled."
  value       = module.networking.nat_gateway_public_ip
}

output "private_endpoint_ips" {
  description = "Private endpoint IPs keyed by endpoint, empty when private endpoints are disabled."
  value       = try(module.private_endpoints[0].private_ip_addresses, {})
}
