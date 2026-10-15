# Naming module contract tests.
#
# Run from the repository root:
#   terraform -chdir=terraform/tests init -backend=false
#   terraform -chdir=terraform/tests test -test-directory=.
#
# The naming module has no providers, so these run entirely offline and
# protect the convention every environment root depends on.

run "prod_names_follow_the_convention" {
  command = plan

  module {
    source = "../modules/naming"
  }

  variables {
    prefix      = "dp"
    workload    = "data"
    environment = "prod"
    location    = "uksouth"
    instance    = "01"
  }

  assert {
    condition     = output.resource_group == "rg-dp-data-prod-uks-01"
    error_message = "Resource group name did not follow <type>-<prefix>-<workload>-<env>-<location>-<instance>."
  }

  assert {
    condition     = output.databricks_workspace == "dbw-dp-data-prod-uks-01"
    error_message = "Databricks workspace name did not follow the convention."
  }

  assert {
    condition     = output.storage_account == "stdpdataprod01"
    error_message = "Storage account name must be the compact (no hyphen) form."
  }

  assert {
    condition     = output.key_vault == "kv-dp-data-prod-01"
    error_message = "Key Vault name must omit the location to stay within 24 characters."
  }

  assert {
    condition     = output.unity_catalog == "dp_data_prod"
    error_message = "Unity Catalog name must use underscores."
  }

  assert {
    condition     = output.location_short == "uks"
    error_message = "uksouth must map to uks."
  }
}

run "preprod_names_stay_within_azure_limits" {
  command = plan

  module {
    source = "../modules/naming"
  }

  variables {
    environment = "preprod"
  }

  assert {
    condition     = length(output.key_vault) <= 24
    error_message = "Key Vault name for preprod exceeds 24 characters."
  }

  assert {
    condition     = length(output.storage_account) <= 24 && can(regex("^[a-z0-9]+$", output.storage_account))
    error_message = "Storage account name for preprod is not 3-24 lowercase alphanumerics."
  }

  assert {
    condition     = output.names["budget"] == "bud-dp-data-preprod-uks-01"
    error_message = "The names map must expose the same values as the individual outputs."
  }
}

run "unknown_region_falls_back_to_first_three_letters" {
  command = plan

  module {
    source = "../modules/naming"
  }

  variables {
    environment = "dev"
    location    = "australiaeast"
  }

  assert {
    condition     = output.location_short == "aus"
    error_message = "Regions without a short code should fall back to the first three letters."
  }
}

run "rejects_an_environment_outside_the_promotion_path" {
  command = plan

  module {
    source = "../modules/naming"
  }

  variables {
    environment = "staging"
  }

  expect_failures = [var.environment]
}

run "rejects_a_prefix_that_is_not_two_to_four_lowercase_letters" {
  command = plan

  module {
    source = "../modules/naming"
  }

  variables {
    prefix      = "DataPlatform"
    environment = "dev"
  }

  expect_failures = [var.prefix]
}

run "rejects_a_workload_containing_separators" {
  command = plan

  module {
    source = "../modules/naming"
  }

  variables {
    workload    = "data-lake"
    environment = "dev"
  }

  expect_failures = [var.workload]
}
