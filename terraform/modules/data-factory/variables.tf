variable "name" {
  description = "Data Factory name (3-63 alphanumerics and hyphens, globally unique)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]$", var.name))
    error_message = "name must be 3-63 alphanumerics or hyphens and must start and end with an alphanumeric."
  }
}

variable "resource_group_name" {
  description = "Resource group the factory is created in."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "uksouth"
}

variable "environment" {
  description = "Environment name exposed to pipelines as the global parameter env."
  type        = string
}

variable "public_network_enabled" {
  description = "Allow public access to the factory endpoints. Set false when a private endpoint is deployed."
  type        = bool
  default     = true
}

variable "key_vault_id" {
  description = "Key Vault the factory reads connection secrets from. A linked service and a Key Vault Secrets User role assignment are created."
  type        = string
}

variable "assign_data_lake_role" {
  description = "Grant the factory identity Storage Blob Data Contributor on data_lake_storage_account_id."
  type        = bool
  default     = false
}

variable "data_lake_storage_account_id" {
  description = "Storage account the factory identity is granted Storage Blob Data Contributor on. Required when assign_data_lake_role is true."
  type        = string
  default     = null
}

variable "create_data_lake_linked_service" {
  description = "Create the ADLS Gen2 linked service (ls_datalake)."
  type        = bool
  default     = false
}

variable "data_lake_dfs_endpoint" {
  description = "DFS endpoint of the data lake (https://<account>.dfs.core.windows.net/). Required when create_data_lake_linked_service is true."
  type        = string
  default     = null
}

variable "create_databricks_linked_service" {
  description = "Create the Databricks linked service (ls_databricks) authenticated with the factory managed identity."
  type        = bool
  default     = false
}

variable "databricks_workspace_url" {
  description = "Databricks workspace host (https://adb-....azuredatabricks.net). Required when create_databricks_linked_service is true."
  type        = string
  default     = null
}

variable "databricks_workspace_id" {
  description = "Azure resource ID of the Databricks workspace, used for managed-identity authentication from the linked service."
  type        = string
  default     = null
}

variable "databricks_cluster" {
  description = "Job cluster shape used by the Databricks linked service."
  type = object({
    node_type       = optional(string, "Standard_DS3_v2")
    cluster_version = optional(string, "15.4.x-scala2.12")
    min_workers     = optional(number, 1)
    max_workers     = optional(number, 4)
  })
  default = {}
}

variable "integration_runtime" {
  description = "Managed-VNet Azure integration runtime settings."
  type = object({
    compute_type     = optional(string, "General")
    core_count       = optional(number, 8)
    time_to_live_min = optional(number, 10)
  })
  default = {}

  validation {
    condition     = contains(["General", "ComputeOptimized", "MemoryOptimized"], var.integration_runtime.compute_type)
    error_message = "integration_runtime.compute_type must be General, ComputeOptimized or MemoryOptimized."
  }
}

variable "managed_private_endpoints" {
  description = "Managed private endpoints created inside the factory's managed VNet, keyed by name. Each approval must still be completed on the target resource."
  type = map(object({
    target_resource_id = string
    subresource_name   = string
  }))
  default = {}
}

variable "git_configuration" {
  description = "Optional Azure DevOps Git integration. Applies to the development factory only; other environments receive ARM templates from the pipeline."
  type = object({
    account_name    = string
    project_name    = string
    repository_name = string
    branch_name     = optional(string, "main")
    root_folder     = optional(string, "/adf")
    tenant_id       = optional(string) # defaults to the deploying tenant
  })
  default = null
}

variable "enable_diagnostics" {
  description = "Create the diagnostic setting. Kept separate from log_analytics_workspace_id so that the toggle is known at plan time even when the workspace is created in the same apply."
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Workspace ID for pipeline, activity and trigger run diagnostics. Required when enable_diagnostics is true."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the factory."
  type        = map(string)
  default     = {}
}
