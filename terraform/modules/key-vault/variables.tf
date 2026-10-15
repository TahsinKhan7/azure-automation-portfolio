variable "name" {
  description = "Key Vault name (3-24 alphanumerics and hyphens, globally unique)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name)) && !can(regex("--", var.name))
    error_message = "name must be 3-24 characters, start with a letter, contain only alphanumerics and single hyphens, and end with an alphanumeric."
  }
}

variable "resource_group_name" {
  description = "Resource group the vault is created in."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "uksouth"
}

variable "sku_name" {
  description = "Vault SKU. premium adds HSM-backed keys."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "sku_name must be standard or premium."
  }
}

variable "soft_delete_retention_days" {
  description = "Days a deleted vault or secret can be recovered (7-90)."
  type        = number
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
  }
}

variable "purge_protection_enabled" {
  description = "Prevent permanent deletion during the retention window. Irreversible once enabled; keep true outside of dev."
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "Allow access from public networks (subject to network_acls). Set false when a private endpoint is deployed."
  type        = bool
  default     = true
}

variable "network_acls_default_action" {
  description = "Default firewall action for traffic not matched by an IP or subnet rule."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_acls_default_action)
    error_message = "network_acls_default_action must be Allow or Deny."
  }
}

variable "allowed_ip_ranges" {
  description = "Public IP addresses or CIDR ranges allowed through the vault firewall (for example build agents)."
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "Subnet IDs allowed through the vault firewall via the Microsoft.KeyVault service endpoint."
  type        = list(string)
  default     = []
}

variable "administrator_object_ids" {
  description = "Entra ID object IDs granted Key Vault Administrator. Normally the platform team group and the deployment identity."
  type        = set(string)
  default     = []
}

variable "secrets_user_object_ids" {
  description = "Entra ID object IDs granted Key Vault Secrets User (read secrets). Typically workload managed identities."
  type        = set(string)
  default     = []
}

variable "enable_diagnostics" {
  description = "Create the diagnostic setting. Kept separate from log_analytics_workspace_id so that the toggle is known at plan time even when the workspace is created in the same apply."
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Workspace ID for audit diagnostics. Required when enable_diagnostics is true."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the vault."
  type        = map(string)
  default     = {}
}
