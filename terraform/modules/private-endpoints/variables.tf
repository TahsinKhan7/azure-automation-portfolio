variable "endpoints" {
  description = <<-EOT
    Map of private endpoints to create, keyed by a short name that is appended to name_prefix.
    Each entry names the target resource, the sub-resource (group ID) and the private DNS zones
    that should receive the A record.
  EOT
  type = map(object({
    resource_id          = string
    subresource_names    = list(string)
    private_dns_zone_ids = optional(list(string), [])
  }))

  validation {
    condition     = alltrue([for k, v in var.endpoints : length(v.subresource_names) > 0])
    error_message = "Every endpoint must specify at least one subresource name (for example vault, dfs, blob, dataFactory, databricks_ui_api)."
  }
}

variable "name_prefix" {
  description = "Prefix for private endpoint names; the map key is appended, for example pe-dp-data-prod-vault."
  type        = string
}

variable "subnet_id" {
  description = "Subnet the private endpoints are placed in."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the private endpoints."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "uksouth"
}

variable "tags" {
  description = "Tags applied to the private endpoints."
  type        = map(string)
  default     = {}
}
