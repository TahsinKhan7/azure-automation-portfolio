variable "name" {
  description = "Storage account name (3-24 lowercase alphanumerics, globally unique)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "name must be 3-24 lowercase letters and digits."
  }
}

variable "resource_group_name" {
  description = "Resource group the account is created in."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "uksouth"
}

variable "account_tier" {
  description = "Performance tier."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "account_tier must be Standard or Premium."
  }
}

variable "replication_type" {
  description = "Replication strategy. LRS/ZRS for lower environments, GRS/GZRS/RAGZRS for production."
  type        = string
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of LRS, ZRS, GRS, GZRS, RAGRS or RAGZRS."
  }
}

variable "access_tier" {
  description = "Default blob access tier."
  type        = string
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool"], var.access_tier)
    error_message = "access_tier must be Hot or Cool."
  }
}

variable "containers" {
  description = "Containers (ADLS Gen2 file systems) to create. Defaults to the medallion layers."
  type        = list(string)
  default     = ["bronze", "silver", "gold"]

  validation {
    condition     = alltrue([for c in var.containers : can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", c)) && !can(regex("--", c))])
    error_message = "Container names must be 3-63 lowercase alphanumerics or single hyphens."
  }
}

variable "shared_access_key_enabled" {
  description = "Allow Shared Key (account key) authentication. Keep false so that all access is through Entra ID."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Allow access from public networks (subject to network_rules). Set false when private endpoints are deployed."
  type        = bool
  default     = true
}

variable "network_rules_default_action" {
  description = "Default firewall action for traffic not matched by an IP or subnet rule."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_rules_default_action)
    error_message = "network_rules_default_action must be Allow or Deny."
  }
}

variable "allowed_ip_ranges" {
  description = "Public IPv4 addresses or CIDR ranges allowed through the firewall. /31 and /32 ranges are not accepted by Azure; use the bare address instead."
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "Subnet IDs allowed through the firewall via the Microsoft.Storage service endpoint."
  type        = list(string)
  default     = []
}

variable "blob_soft_delete_days" {
  description = "Days deleted blobs are retained (1-365). 0 disables."
  type        = number
  default     = 30

  validation {
    condition     = var.blob_soft_delete_days >= 0 && var.blob_soft_delete_days <= 365
    error_message = "blob_soft_delete_days must be between 0 and 365."
  }
}

variable "container_soft_delete_days" {
  description = "Days deleted containers are retained (1-365). 0 disables."
  type        = number
  default     = 30

  validation {
    condition     = var.container_soft_delete_days >= 0 && var.container_soft_delete_days <= 365
    error_message = "container_soft_delete_days must be between 0 and 365."
  }
}

variable "lifecycle_rules" {
  description = "Lifecycle tiering rules keyed by rule name. Blobs under prefix_match are moved to cool, then archive, then deleted after the given number of days since modification; null skips that step."
  type = map(object({
    prefix_match         = list(string)
    tier_to_cool_days    = optional(number)
    tier_to_archive_days = optional(number)
    delete_days          = optional(number)
  }))
  default = {
    bronze = {
      prefix_match         = ["bronze/"]
      tier_to_cool_days    = 90
      tier_to_archive_days = 365
    }
  }
}

variable "blob_data_contributor_principal_ids" {
  description = "Map of friendly name to principal object ID granted Storage Blob Data Contributor on the account (for example the Databricks access connector and the Data Factory identity)."
  type        = map(string)
  default     = {}
}

variable "blob_data_reader_principal_ids" {
  description = "Map of friendly name to principal object ID granted Storage Blob Data Reader on the account."
  type        = map(string)
  default     = {}
}

variable "enable_diagnostics" {
  description = "Create the diagnostic setting. Kept separate from log_analytics_workspace_id so that the toggle is known at plan time even when the workspace is created in the same apply."
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Workspace ID for blob service diagnostics. Required when enable_diagnostics is true."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the account."
  type        = map(string)
  default     = {}
}
