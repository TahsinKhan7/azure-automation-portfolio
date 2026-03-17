variable "storage_account_name" { type = string }
variable "resource_group_name"  { type = string }
variable "location"             { type = string; default = "uksouth" }
variable "replication_type"     { type = string; default = "GRS" }
variable "allowed_ip_ranges"    { type = list(string); default = [] }
variable "tags"                 { type = map(string); default = {} }
