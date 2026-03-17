variable "vnet_name"               { type = string }
variable "resource_group_name"     { type = string }
variable "location"                { type = string; default = "uksouth" }
variable "address_space"           { type = list(string); default = ["10.0.0.0/16"] }
variable "databricks_public_cidr"  { type = string; default = "10.0.1.0/24" }
variable "databricks_private_cidr" { type = string; default = "10.0.2.0/24" }
variable "tags"                    { type = map(string); default = {} }
