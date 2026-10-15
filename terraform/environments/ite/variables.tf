# ------------------------------------------------------------------------------
# Root variables. Every value is supplied by terraform.tfvars in this folder;
# defaults here represent the lowest-cost, least-privileged configuration so
# that a missing tfvars value never silently produces a production-sized bill.
# ------------------------------------------------------------------------------

# ---- Identity of the environment ------------------------------------------------

variable "environment" {
  description = "Deployment environment. Must match the folder name."
  type        = string

  validation {
    condition     = contains(["dev", "ite", "iqe", "preprod", "prod"], var.environment)
    error_message = "environment must be one of: dev, ite, iqe, preprod, prod."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "uksouth"
}

variable "prefix" {
  description = "Platform prefix embedded in every resource name."
  type        = string
  default     = "dp"
}

variable "workload" {
  description = "Workload identifier embedded in every resource name."
  type        = string
  default     = "data"
}

variable "instance" {
  description = "Two-digit instance number."
  type        = string
  default     = "01"
}

variable "cost_centre" {
  description = "Cost centre tag applied to every resource and enforced on Databricks clusters."
  type        = string
  default     = "CC-0000"
}

variable "tags" {
  description = "Additional tags merged with the standard set (Environment, Platform, Workload, CostCentre, ManagedBy)."
  type        = map(string)
  default     = {}
}

# ---- Governance ----------------------------------------------------------------------

variable "resource_lock_level" {
  description = "Management lock on the resource group (null, CanNotDelete or ReadOnly)."
  type        = string
  default     = null
}

variable "budget_amount" {
  description = "Monthly budget in GBP. null disables the budget."
  type        = number
  default     = null
}

variable "budget_start_date" {
  description = "Budget start (first of a month, RFC 3339)."
  type        = string
  default     = "2026-11-01T00:00:00Z"
}

variable "budget_contact_emails" {
  description = "Recipients of budget notifications."
  type        = list(string)
  default     = []
}

# ---- Observability --------------------------------------------------------------------

variable "log_retention_in_days" {
  description = "Log Analytics interactive retention."
  type        = number
  default     = 30
}

variable "log_daily_quota_gb" {
  description = "Log Analytics daily ingestion cap in GB (-1 for none)."
  type        = number
  default     = 1
}

# ---- Networking -------------------------------------------------------------------------

variable "address_space" {
  description = "VNet address space."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_cidrs" {
  description = "Subnet CIDRs carved from address_space."
  type = object({
    databricks_public  = string
    databricks_private = string
    private_endpoints  = string
  })
  default = {
    databricks_public  = "10.0.1.0/24"
    databricks_private = "10.0.2.0/24"
    private_endpoints  = "10.0.3.0/24"
  }
}

variable "enable_nat_gateway" {
  description = "Create a NAT gateway for Databricks egress."
  type        = bool
  default     = false
}

variable "enable_private_endpoints" {
  description = "Create private endpoints for Key Vault, storage, Data Factory and Databricks, and disable public network access on those services."
  type        = bool
  default     = false
}

variable "private_dns_zones_to_create" {
  description = "Private DNS zones this environment creates and links itself (single-VNet estates)."
  type        = list(string)
  default     = []
}

variable "private_dns_zone_ids" {
  description = "Map of zone name to zone ID for zones hosted centrally (hub). Takes precedence over private_dns_zones_to_create."
  type        = map(string)
  default     = {}
}

variable "allowed_ip_ranges" {
  description = "Public IPs or CIDRs allowed through the Key Vault and storage firewalls (build agents, office egress)."
  type        = list(string)
  default     = []
}

# ---- Identity and access -----------------------------------------------------------

variable "platform_admin_object_ids" {
  description = "Entra ID object IDs granted Key Vault Administrator."
  type        = set(string)
  default     = []
}

variable "secrets_reader_object_ids" {
  description = "Entra ID object IDs granted Key Vault Secrets User."
  type        = set(string)
  default     = []
}

variable "lake_contributor_object_ids" {
  description = "Map of friendly name to object ID granted Storage Blob Data Contributor on the lake."
  type        = map(string)
  default     = {}
}

variable "lake_reader_object_ids" {
  description = "Map of friendly name to object ID granted Storage Blob Data Reader on the lake."
  type        = map(string)
  default     = {}
}

# ---- Key Vault -----------------------------------------------------------------------------

variable "key_vault_sku" {
  description = "Key Vault SKU."
  type        = string
  default     = "standard"
}

variable "key_vault_purge_protection_enabled" {
  description = "Enable purge protection. Irreversible; disable only in short-lived environments."
  type        = bool
  default     = true
}

# ---- Storage ----------------------------------------------------------------------------------

variable "storage_replication_type" {
  description = "Lake storage replication (LRS, ZRS, GRS, GZRS, RAGRS, RAGZRS)."
  type        = string
  default     = "LRS"
}

variable "storage_containers" {
  description = "Containers created in the lake. Must include every Unity Catalog schema and the catalog storage container."
  type        = list(string)
  default     = ["bronze", "silver", "gold", "catalog"]
}

variable "storage_soft_delete_days" {
  description = "Blob and container soft-delete retention in days."
  type        = number
  default     = 7
}

variable "storage_lifecycle_rules" {
  description = "Lifecycle tiering rules keyed by rule name."
  type = map(object({
    prefix_match         = list(string)
    tier_to_cool_days    = optional(number)
    tier_to_archive_days = optional(number)
    delete_days          = optional(number)
  }))
  default = {}
}

# ---- Databricks --------------------------------------------------------------------------

variable "databricks_sku" {
  description = "Workspace SKU. premium is required for Unity Catalog."
  type        = string
  default     = "premium"
}

variable "databricks_no_public_ip" {
  description = "Secure cluster connectivity (no public IPs on cluster nodes)."
  type        = bool
  default     = true
}

variable "databricks_public_network_access_enabled" {
  description = "Allow the workspace UI/API from the internet. false requires the databricks_ui_api and browser_authentication private endpoints."
  type        = bool
  default     = true
}

variable "databricks_pool" {
  description = "Shared instance pool sizing."
  type = object({
    node_type_id       = optional(string, "Standard_DS3_v2")
    max_capacity       = optional(number, 10)
    min_idle_instances = optional(number, 0)
    availability       = optional(string, "SPOT_AZURE")
  })
  default = {}
}

variable "databricks_max_workers" {
  description = "Maximum autoscale workers permitted by cluster policies."
  type        = number
  default     = 4
}

variable "databricks_interactive_autotermination_minutes" {
  description = "Maximum idle minutes for interactive clusters."
  type        = number
  default     = 30
}

variable "databricks_policy_users" {
  description = "Groups allowed to use each cluster policy (job, shared, single_node)."
  type        = map(list(string))
  default = {
    job         = ["data-engineers"]
    shared      = ["data-engineers", "data-analysts"]
    single_node = ["data-engineers", "data-scientists"]
  }
}

# ---- Data Factory ---------------------------------------------------------------------

variable "data_factory_databricks_cluster" {
  description = "Job cluster shape for the Data Factory Databricks linked service."
  type = object({
    node_type       = optional(string, "Standard_DS3_v2")
    cluster_version = optional(string, "15.4.x-scala2.12")
    min_workers     = optional(number, 1)
    max_workers     = optional(number, 2)
  })
  default = {}
}

variable "data_factory_git_configuration" {
  description = "Azure DevOps Git integration. Set only for the development factory."
  type = object({
    account_name    = string
    project_name    = string
    repository_name = string
    branch_name     = optional(string, "main")
    root_folder     = optional(string, "/adf")
    tenant_id       = optional(string)
  })
  default = null
}

# ---- Unity Catalog ----------------------------------------------------------------------

variable "unity_catalog_metastore_id" {
  description = "Regional metastore ID to assign. null when the assignment is managed at account level."
  type        = string
  default     = null
}

variable "unity_catalog_schemas" {
  description = "Schemas (and matching external locations) created in the environment catalog."
  type        = list(string)
  default     = ["bronze", "silver", "gold"]
}

variable "unity_catalog_storage_container" {
  description = "Container used as the catalog's managed storage root."
  type        = string
  default     = "catalog"
}

variable "unity_catalog_owner_group" {
  description = "Account group that owns the catalog and schemas."
  type        = string
  default     = null
}

variable "unity_catalog_grants" {
  description = "Catalog privileges keyed by group."
  type        = map(list(string))
  default = {
    data-engineers = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY", "CREATE_TABLE", "CREATE_SCHEMA"]
    data-analysts  = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
  }
}

variable "unity_catalog_schema_grants" {
  description = "Additional schema privileges keyed by schema then group."
  type        = map(map(list(string)))
  default     = {}
}

variable "unity_catalog_skip_validation" {
  description = "Skip external location validation during bootstrap."
  type        = bool
  default     = false
}
