variable "catalog_name" {
  description = "Catalog name (letters, digits and underscores)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{1,62}$", var.catalog_name))
    error_message = "catalog_name must start with a letter and contain only lowercase letters, digits and underscores."
  }
}

variable "environment" {
  description = "Environment name, recorded as a catalog property and in comments."
  type        = string
}

variable "workspace_id" {
  description = "Numeric Databricks workspace ID, used for metastore assignment and the catalog workspace binding."
  type        = number
}

variable "metastore_id" {
  description = "ID of the regional Unity Catalog metastore to assign to the workspace. null assumes the assignment already exists (for example through account-level automation)."
  type        = string
  default     = null
}

variable "access_connector_id" {
  description = "Resource ID of the Databricks access connector used by the storage credential."
  type        = string
}

variable "storage_account_name" {
  description = "ADLS Gen2 account hosting the lake containers."
  type        = string
}

variable "schemas" {
  description = "Schemas to create in the catalog. Each schema also gets an external location pointing at the container of the same name."
  type        = list(string)
  default     = ["bronze", "silver", "gold"]

  validation {
    condition     = alltrue([for s in var.schemas : can(regex("^[a-z][a-z0-9_]{1,62}$", s))])
    error_message = "Schema names must start with a letter and contain only lowercase letters, digits and underscores."
  }
}

variable "catalog_storage_container" {
  description = "Container used as the catalog's managed storage root. null uses the metastore default location."
  type        = string
  default     = null
}

variable "isolation_mode" {
  description = "ISOLATED binds the catalog to this workspace only; OPEN makes it visible to every workspace on the metastore."
  type        = string
  default     = "ISOLATED"

  validation {
    condition     = contains(["ISOLATED", "OPEN"], var.isolation_mode)
    error_message = "isolation_mode must be ISOLATED or OPEN."
  }
}

variable "catalog_owner" {
  description = "Account group that owns the catalog, schemas and external locations. null leaves the deploying principal as owner."
  type        = string
  default     = null
}

variable "catalog_grants" {
  description = "Privileges granted on the catalog, keyed by account group name."
  type        = map(list(string))
  default = {
    data-engineers = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY", "CREATE_TABLE", "CREATE_SCHEMA"]
    data-analysts  = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
  }
}

variable "schema_grants" {
  description = "Additional privileges per schema, keyed by schema name then group name. Use this to tighten or widen access to individual layers (for example analysts on gold only)."
  type        = map(map(list(string)))
  default     = {}
}

variable "external_location_grants" {
  description = "Privileges granted on every external location, keyed by account group name."
  type        = map(list(string))
  default = {
    data-engineers = ["READ_FILES", "WRITE_FILES"]
  }
}

variable "skip_validation" {
  description = "Skip connectivity validation when creating external locations. Only set true when the deploying principal cannot reach storage (for example during initial bootstrap)."
  type        = bool
  default     = false
}
