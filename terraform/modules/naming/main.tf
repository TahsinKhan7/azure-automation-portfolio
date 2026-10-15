# ------------------------------------------------------------------------------
# Naming module
#
# A pure, provider-free module that turns {prefix, workload, environment,
# location, instance} into the standard resource names used across the
# platform. Centralising the convention here means every environment root
# and every module receives identical names, and a change to the convention
# is a single-file change.
#
# Convention
#   <type>-<prefix>-<workload>-<environment>-<location>-<instance>
#   e.g. rg-dp-data-prod-uks-01
#
# Resources with restrictive naming rules (storage accounts, Key Vault,
# Unity Catalog) have dedicated shapes documented alongside each local.
# ------------------------------------------------------------------------------

locals {
  location_short = lookup(var.location_short_codes, var.location, substr(var.location, 0, 3))

  # Core building blocks
  base          = "${var.prefix}-${var.workload}-${var.environment}"
  base_location = "${local.base}-${local.location_short}-${var.instance}"

  # Alphanumeric-only form used where hyphens are not allowed (storage accounts).
  compact = "${var.prefix}${var.workload}${var.environment}${var.instance}"

  names = {
    resource_group                    = "rg-${local.base_location}"
    virtual_network                   = "vnet-${local.base_location}"
    network_security_group            = "nsg-${local.base_location}"
    nat_gateway                       = "ng-${local.base_location}"
    public_ip                         = "pip-${local.base_location}"
    log_analytics_workspace           = "log-${local.base_location}"
    data_factory                      = "adf-${local.base_location}"
    databricks_workspace              = "dbw-${local.base_location}"
    databricks_managed_resource_group = "rg-${local.base}-${local.location_short}-dbw-managed"
    databricks_access_connector       = "dbac-${local.base_location}"
    databricks_instance_pool          = "pool-${local.base}-shared"
    budget                            = "bud-${local.base_location}"
    private_endpoint_prefix           = "pe-${local.base}"

    # Key Vault: 3-24 chars, alphanumerics and hyphens, globally unique.
    # Location is omitted so that "preprod" still fits within the limit.
    key_vault = "kv-${local.base}-${var.instance}"

    # Storage account: 3-24 chars, lowercase alphanumerics only, globally unique.
    storage_account = "st${local.compact}"

    # Unity Catalog object names only allow letters, digits and underscores.
    unity_catalog = replace(local.base, "-", "_")
  }
}
