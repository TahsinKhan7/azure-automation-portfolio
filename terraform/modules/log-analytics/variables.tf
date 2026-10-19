variable "name" {
  description = "Log Analytics workspace name."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{2,61}[a-zA-Z0-9]$", var.name))
    error_message = "name must be 4-63 alphanumerics or hyphens and must start and end with an alphanumeric."
  }
}

variable "resource_group_name" {
  description = "Resource group the workspace is created in."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "uksouth"
}

variable "sku" {
  description = "Pricing tier. PerGB2018 is pay-as-you-go; CapacityReservation suits predictable high-volume environments."
  type        = string
  default     = "PerGB2018"

  validation {
    condition     = contains(["PerGB2018", "CapacityReservation", "Free", "Standalone", "PerNode"], var.sku)
    error_message = "sku must be one of PerGB2018, CapacityReservation, Free, Standalone or PerNode."
  }
}

variable "retention_in_days" {
  description = "Interactive retention in days (30-730)."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "retention_in_days must be between 30 and 730."
  }
}

variable "daily_quota_gb" {
  description = "Daily ingestion cap in GB. -1 disables the cap. Lower environments should always set a cap."
  type        = number
  default     = -1

  validation {
    condition     = var.daily_quota_gb == -1 || var.daily_quota_gb >= 0.023
    error_message = "daily_quota_gb must be -1 (unlimited) or at least 0.023 GB."
  }
}

variable "internet_ingestion_enabled" {
  description = "Allow ingestion over the public internet. Disable when Azure Monitor Private Link Scope is in use."
  type        = bool
  default     = true
}

variable "internet_query_enabled" {
  description = "Allow queries over the public internet."
  type        = bool
  default     = true
}

variable "diagnostic_targets" {
  description = "Map of friendly name to resource ID. A diagnostic setting sending all logs and metrics to this workspace is created for each entry."
  type        = map(string)
  default     = {}
}

variable "diagnostic_log_category_group" {
  description = "Log category group sent by the diagnostic settings helper. allLogs or audit."
  type        = string
  default     = "allLogs"

  validation {
    condition     = contains(["allLogs", "audit"], var.diagnostic_log_category_group)
    error_message = "diagnostic_log_category_group must be allLogs or audit."
  }
}

variable "tags" {
  description = "Tags applied to the workspace."
  type        = map(string)
  default     = {}
}
