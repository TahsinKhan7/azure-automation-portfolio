variable "workspace_name"             { type = string }
variable "resource_group_name"        { type = string }
variable "location"                   { type = string; default = "uksouth" }
variable "sku"                        { type = string; default = "premium" }
variable "no_public_ip"               { type = bool;   default = true }
variable "vnet_id"                    { type = string }
variable "public_subnet_name"         { type = string }
variable "private_subnet_name"        { type = string }
variable "public_subnet_nsg_id"       { type = string }
variable "private_subnet_nsg_id"      { type = string }
variable "log_analytics_workspace_id" { type = string; default = null }
variable "tags"                       { type = map(string); default = {} }
