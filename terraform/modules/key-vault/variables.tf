variable "key_vault_name"      { type = string }
variable "resource_group_name" { type = string }
variable "location"            { type = string; default = "uksouth" }
variable "allowed_ip_ranges"   { type = list(string); default = [] }
variable "tags"                { type = map(string); default = {} }
