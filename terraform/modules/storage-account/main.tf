# ------------------------------------------------------------------------------
# ADLS Gen2 storage account for the lakehouse.
#
#  - Hierarchical namespace on, Shared Key off, public blob access off,
#    TLS 1.2 minimum, infrastructure encryption on.
#  - Containers are created through the management plane
#    (storage_account_id) so that a Deny firewall does not block the
#    pipeline agent during apply.
#  - Lifecycle rules tier raw data to cool/archive; soft delete protects
#    against accidental deletes.
# ------------------------------------------------------------------------------

resource "azurerm_storage_account" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = var.account_tier
  account_replication_type = var.replication_type
  access_tier              = var.access_tier
  is_hns_enabled           = true

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = var.shared_access_key_enabled
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  public_network_access_enabled     = var.public_network_access_enabled
  infrastructure_encryption_enabled = true
  cross_tenant_replication_enabled  = false

  identity {
    type = "SystemAssigned"
  }

  blob_properties {
    dynamic "delete_retention_policy" {
      for_each = var.blob_soft_delete_days > 0 ? [1] : []
      content {
        days = var.blob_soft_delete_days
      }
    }

    dynamic "container_delete_retention_policy" {
      for_each = var.container_soft_delete_days > 0 ? [1] : []
      content {
        days = var.container_soft_delete_days
      }
    }
  }

  network_rules {
    default_action             = var.network_rules_default_action
    bypass                     = ["AzureServices"]
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  tags = var.tags
}

resource "azurerm_storage_container" "this" {
  for_each = toset(var.containers)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "this" {
  count = length(var.lifecycle_rules) > 0 ? 1 : 0

  storage_account_id = azurerm_storage_account.this.id

  dynamic "rule" {
    for_each = var.lifecycle_rules

    content {
      name    = rule.key
      enabled = true

      filters {
        blob_types   = ["blockBlob"]
        prefix_match = rule.value.prefix_match
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_modification_greater_than    = rule.value.tier_to_cool_days
          tier_to_archive_after_days_since_modification_greater_than = rule.value.tier_to_archive_days
          delete_after_days_since_modification_greater_than          = rule.value.delete_days
        }

        snapshot {
          delete_after_days_since_creation_greater_than = 90
        }
      }
    }
  }
}

resource "azurerm_role_assignment" "blob_contributors" {
  for_each = var.blob_data_contributor_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "blob_readers" {
  for_each = var.blob_data_reader_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
}

resource "azurerm_monitor_diagnostic_setting" "blob" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-${var.name}-blob"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  metric {
    category = "Transaction"
  }

  lifecycle {
    precondition {
      condition     = var.log_analytics_workspace_id != null
      error_message = "log_analytics_workspace_id must be set when enable_diagnostics is true."
    }
  }
}
