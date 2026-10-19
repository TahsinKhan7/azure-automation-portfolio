variable "environment" {
  description = "Environment name, embedded in policy names and enforced as a cluster tag."
  type        = string
}

variable "cost_centre" {
  description = "Cost centre tag value every policy forces onto clusters."
  type        = string
}

variable "instance_pool_name" {
  description = "Name of the shared instance pool."
  type        = string
}

variable "pool_node_type_id" {
  description = "VM SKU of the pooled instances."
  type        = string
  default     = "Standard_DS3_v2"
}

variable "pool_max_capacity" {
  description = "Upper bound on pooled instances (idle plus in use). Caps spend from runaway autoscaling."
  type        = number
  default     = 20

  validation {
    condition     = var.pool_max_capacity >= 1 && var.pool_max_capacity <= 1000
    error_message = "pool_max_capacity must be between 1 and 1000."
  }
}

variable "pool_min_idle_instances" {
  description = "Warm instances kept ready. 0 in lower environments; a small number in prod shortens job start-up."
  type        = number
  default     = 0
}

variable "pool_availability" {
  description = "Capacity type of pooled instances. SPOT_AZURE is cheaper but may be evicted; use ON_DEMAND_AZURE for production SLAs. Pools do not support spot-with-fallback."
  type        = string
  default     = "SPOT_AZURE"

  validation {
    condition     = contains(["SPOT_AZURE", "ON_DEMAND_AZURE"], var.pool_availability)
    error_message = "pool_availability must be SPOT_AZURE or ON_DEMAND_AZURE."
  }
}

variable "pool_idle_autotermination_minutes" {
  description = "Minutes an idle pooled instance survives before release."
  type        = number
  default     = 15
}

variable "spark_version" {
  description = "Databricks Runtime pinned for pooled instances and allowed by policies. Use an LTS version."
  type        = string
  default     = "15.4.x-scala2.12"
}

variable "allowed_node_type_ids" {
  description = "VM SKUs that interactive clusters may use."
  type        = list(string)
  default     = ["Standard_DS3_v2", "Standard_DS4_v2", "Standard_E4ds_v5", "Standard_E8ds_v5"]
}

variable "max_workers" {
  description = "Maximum autoscale workers for job and shared clusters."
  type        = number
  default     = 8
}

variable "interactive_autotermination_minutes" {
  description = "Maximum idle minutes before an interactive cluster terminates."
  type        = number
  default     = 60

  validation {
    condition     = var.interactive_autotermination_minutes >= 10 && var.interactive_autotermination_minutes <= 120
    error_message = "interactive_autotermination_minutes must be between 10 and 120."
  }
}

variable "policy_users" {
  description = "Map of policy key (job, shared, single_node) to the groups allowed to use it."
  type        = map(list(string))
  default = {
    job         = ["data-engineers"]
    shared      = ["data-engineers", "data-analysts"]
    single_node = ["data-engineers", "data-scientists"]
  }

  validation {
    condition     = alltrue([for k in keys(var.policy_users) : contains(["job", "shared", "single_node"], k)])
    error_message = "policy_users keys must be job, shared or single_node."
  }
}

variable "max_clusters_per_user" {
  description = "Maximum clusters a single user may create from the interactive policies."
  type        = number
  default     = 2
}
