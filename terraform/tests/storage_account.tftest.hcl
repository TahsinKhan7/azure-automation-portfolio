# Storage account module tests.
#
# Run from the repository root:
#   terraform -chdir=terraform/tests init -backend=false
#   terraform -chdir=terraform/tests test -test-directory=.
#
# A mocked azurerm provider lets the plan run without credentials. Assertions
# cover the security posture that must never regress and the input
# validations that protect against bad tfvars.

mock_provider "azurerm" {}

run "account_is_hardened_by_default" {
  command = plan

  module {
    source = "../modules/storage-account"
  }

  variables {
    name                = "stdpdatadev01"
    resource_group_name = "rg-dp-data-dev-uks-01"
    location            = "uksouth"
  }

  assert {
    condition     = azurerm_storage_account.this.is_hns_enabled == true
    error_message = "Hierarchical namespace must be enabled for ADLS Gen2."
  }

  assert {
    condition     = azurerm_storage_account.this.min_tls_version == "TLS1_2"
    error_message = "Minimum TLS version must be 1.2."
  }

  assert {
    condition     = azurerm_storage_account.this.https_traffic_only_enabled == true
    error_message = "HTTPS-only traffic must be enforced."
  }

  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false
    error_message = "Shared Key access must be disabled by default."
  }

  assert {
    condition     = azurerm_storage_account.this.allow_nested_items_to_be_public == false
    error_message = "Anonymous blob access must be disabled."
  }

  assert {
    condition     = azurerm_storage_account.this.network_rules[0].default_action == "Deny"
    error_message = "The storage firewall must deny by default."
  }

  assert {
    condition     = azurerm_storage_account.this.infrastructure_encryption_enabled == true
    error_message = "Infrastructure encryption must be enabled."
  }

  assert {
    condition     = length(azurerm_storage_container.this) == 3
    error_message = "The default container set must be the three medallion layers."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.blob) == 0
    error_message = "No diagnostic setting should be created without a Log Analytics workspace."
  }
}

run "soft_delete_can_be_disabled_with_zero_days" {
  command = plan

  module {
    source = "../modules/storage-account"
  }

  variables {
    name                       = "stdpdatadev01"
    resource_group_name        = "rg-dp-data-dev-uks-01"
    blob_soft_delete_days      = 0
    container_soft_delete_days = 0
  }

  assert {
    condition     = length(azurerm_storage_account.this.blob_properties[0].delete_retention_policy) == 0
    error_message = "A zero-day setting must omit the blob delete retention policy block."
  }

  assert {
    condition     = length(azurerm_storage_account.this.blob_properties[0].container_delete_retention_policy) == 0
    error_message = "A zero-day setting must omit the container delete retention policy block."
  }
}

run "lifecycle_policy_is_only_created_when_rules_exist" {
  command = plan

  module {
    source = "../modules/storage-account"
  }

  variables {
    name                = "stdpdatadev01"
    resource_group_name = "rg-dp-data-dev-uks-01"
    lifecycle_rules     = {}
  }

  assert {
    condition     = length(azurerm_storage_management_policy.this) == 0
    error_message = "An empty lifecycle_rules map must not create a management policy."
  }
}

run "diagnostics_are_created_when_enabled" {
  command = plan

  module {
    source = "../modules/storage-account"
  }

  variables {
    name                       = "stdpdatadev01"
    resource_group_name        = "rg-dp-data-dev-uks-01"
    enable_diagnostics         = true
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dp-data-dev-uks-01/providers/Microsoft.OperationalInsights/workspaces/log-dp-data-dev-uks-01"
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.blob) == 1
    error_message = "A diagnostic setting must be created when enable_diagnostics is true."
  }
}

run "diagnostics_require_a_workspace_id" {
  command = plan

  module {
    source = "../modules/storage-account"
  }

  variables {
    name                = "stdpdatadev01"
    resource_group_name = "rg-dp-data-dev-uks-01"
    enable_diagnostics  = true
  }

  # The precondition on the diagnostic setting should reject the plan.
  expect_failures = [
    azurerm_monitor_diagnostic_setting.blob,
  ]
}

run "rejects_a_name_with_uppercase_or_hyphens" {
  command = plan

  module {
    source = "../modules/storage-account"
  }

  variables {
    name                = "St-Data-Dev"
    resource_group_name = "rg-dp-data-dev-uks-01"
  }

  expect_failures = [var.name]
}

run "rejects_an_unsupported_replication_type" {
  command = plan

  module {
    source = "../modules/storage-account"
  }

  variables {
    name                = "stdpdatadev01"
    resource_group_name = "rg-dp-data-dev-uks-01"
    replication_type    = "RA-GRS"
  }

  expect_failures = [var.replication_type]
}

run "rejects_a_container_name_with_consecutive_hyphens" {
  command = plan

  module {
    source = "../modules/storage-account"
  }

  variables {
    name                = "stdpdatadev01"
    resource_group_name = "rg-dp-data-dev-uks-01"
    containers          = ["bronze", "raw--landing"]
  }

  expect_failures = [var.containers]
}
