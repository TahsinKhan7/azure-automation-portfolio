output "instance_pool_id" {
  description = "ID of the shared instance pool."
  value       = databricks_instance_pool.shared.id
}

output "policy_ids" {
  description = "Map of policy key (job, shared, single_node) to cluster policy ID. Pass the job policy ID to Data Factory and Workflows."
  value       = { for k, v in databricks_cluster_policy.this : k => v.id }
}

output "policy_names" {
  description = "Map of policy key to policy display name."
  value       = { for k, v in databricks_cluster_policy.this : k => v.name }
}
