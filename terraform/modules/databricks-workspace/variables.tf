variable "name" {
  description = "Databricks workspace name."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{3,64}$", var.name))
    error_message = "name must be 3-64 alphanumerics, hyphens or underscores."
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
  description = "Workspace tier. premium is required for Unity Catalog, cluster policies and RBAC features used elsewhere in this repository."
  type        = string
  default     = "premium"

  validation {
    condition     = contains(["standard", "premium", "trial"], var.sku)
    error_message = "sku must be standard, premium or trial."
  }
}

variable "managed_resource_group_name" {
  description = "Name of the managed resource group Databricks creates for workspace infrastructure."
  type        = string
}

variable "vnet_id" {
  description = "ID of the VNet the workspace is injected into."
  type        = string
}

variable "public_subnet_name" {
  description = "Name of the delegated host subnet."
  type        = string
}

variable "private_subnet_name" {
  description = "Name of the delegated container subnet."
  type        = string
}

variable "public_subnet_nsg_association_id" {
  description = "NSG association ID of the host subnet."
  type        = string
}

variable "private_subnet_nsg_association_id" {
  description = "NSG association ID of the container subnet."
  type        = string
}

variable "no_public_ip" {
  description = "Enable secure cluster connectivity (clusters have no public IPs). Requires NAT gateway or firewall egress."
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "Allow the workspace UI and APIs to be reached from the public internet. false requires a front-end private endpoint."
  type        = bool
  default     = true
}

variable "access_connector_name" {
  description = "Name of the Databricks access connector whose managed identity Unity Catalog uses to reach storage."
  type        = string
}

variable "assign_storage_role" {
  description = "Grant the access connector Storage Blob Data Contributor on storage_account_id."
  type        = bool
  default     = false
}

variable "storage_account_id" {
  description = "Storage account the access connector is granted Storage Blob Data Contributor on. Required when assign_storage_role is true."
  type        = string
  default     = null
}

variable "enable_diagnostics" {
  description = "Create the diagnostic setting. Kept separate from log_analytics_workspace_id so that the toggle is known at plan time even when the workspace is created in the same apply."
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Workspace ID for workspace diagnostics (clusters, jobs, notebooks, Unity Catalog audit). Required when enable_diagnostics is true."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the workspace and access connector."
  type        = map(string)
  default     = {}
}
