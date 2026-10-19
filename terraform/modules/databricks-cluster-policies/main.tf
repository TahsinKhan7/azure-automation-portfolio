# ------------------------------------------------------------------------------
# Cluster policies and a shared instance pool for cost control.
#
# Policies pin what matters for spend and governance (auto-termination,
# node types, worker caps, mandatory tags, runtime) and leave the rest to
# users. The pool keeps job-cluster start-up fast without paying for idle
# capacity in every environment; spot instances are used where interruption
# is acceptable and interactive clusters fall back to on-demand automatically.
# ------------------------------------------------------------------------------

locals {
  mandatory_tags = {
    "custom_tags.CostCentre" = {
      type  = "fixed"
      value = var.cost_centre
    }
    "custom_tags.Environment" = {
      type  = "fixed"
      value = var.environment
    }
  }

  policies = {
    job = {
      name         = "dp-${var.environment}-job-cluster"
      description  = "Job clusters created by Data Factory and Workflows. Pooled nodes, autoscale capped, photon on."
      max_per_user = null
      definition = merge(local.mandatory_tags, {
        "cluster_type" = {
          type  = "fixed"
          value = "job"
        }
        "instance_pool_id" = {
          type  = "fixed"
          value = databricks_instance_pool.shared.id
        }
        "driver_instance_pool_id" = {
          type  = "fixed"
          value = databricks_instance_pool.shared.id
        }
        "spark_version" = {
          type  = "fixed"
          value = var.spark_version
        }
        "autoscale.min_workers" = {
          type         = "range"
          minValue     = 1
          maxValue     = 2
          defaultValue = 1
        }
        "autoscale.max_workers" = {
          type         = "range"
          minValue     = 1
          maxValue     = var.max_workers
          defaultValue = min(4, var.max_workers)
        }
        "runtime_engine" = {
          type  = "fixed"
          value = "PHOTON"
        }
        "data_security_mode" = {
          type  = "fixed"
          value = "SINGLE_USER"
        }
      })
    }

    shared = {
      name         = "dp-${var.environment}-shared-interactive"
      description  = "Shared interactive clusters for exploration. Short auto-termination, approved SKUs only."
      max_per_user = var.max_clusters_per_user
      definition = merge(local.mandatory_tags, {
        "cluster_type" = {
          type  = "fixed"
          value = "all-purpose"
        }
        "autotermination_minutes" = {
          type         = "range"
          minValue     = 10
          maxValue     = var.interactive_autotermination_minutes
          defaultValue = min(30, var.interactive_autotermination_minutes)
        }
        "node_type_id" = {
          type         = "allowlist"
          values       = var.allowed_node_type_ids
          defaultValue = var.allowed_node_type_ids[0]
        }
        "driver_node_type_id" = {
          type         = "allowlist"
          values       = var.allowed_node_type_ids
          defaultValue = var.allowed_node_type_ids[0]
        }
        "autoscale.max_workers" = {
          type         = "range"
          minValue     = 1
          maxValue     = var.max_workers
          defaultValue = 2
        }
        "spark_version" = {
          type    = "regex"
          pattern = "1[4-9]\\.[0-9]+\\.x-scala.*"
        }
        "data_security_mode" = {
          type  = "fixed"
          value = "USER_ISOLATION"
        }
        "azure_attributes.availability" = {
          type  = "fixed"
          value = "SPOT_WITH_FALLBACK_AZURE"
        }
      })
    }

    single_node = {
      name         = "dp-${var.environment}-single-node"
      description  = "Single-node clusters for development and small ML experiments."
      max_per_user = var.max_clusters_per_user
      definition = merge(local.mandatory_tags, {
        "cluster_type" = {
          type  = "fixed"
          value = "all-purpose"
        }
        "num_workers" = {
          type  = "fixed"
          value = 0
        }
        "spark_conf.spark.databricks.cluster.profile" = {
          type  = "fixed"
          value = "singleNode"
        }
        "spark_conf.spark.master" = {
          type  = "fixed"
          value = "local[*]"
        }
        "custom_tags.ResourceClass" = {
          type  = "fixed"
          value = "SingleNode"
        }
        "node_type_id" = {
          type         = "allowlist"
          values       = var.allowed_node_type_ids
          defaultValue = var.allowed_node_type_ids[0]
        }
        "autotermination_minutes" = {
          type         = "range"
          minValue     = 10
          maxValue     = var.interactive_autotermination_minutes
          defaultValue = 30
        }
        "data_security_mode" = {
          type  = "fixed"
          value = "SINGLE_USER"
        }
      })
    }
  }

  policy_user_pairs = flatten([
    for policy_key, groups in var.policy_users : [
      for group in groups : {
        key    = "${policy_key}:${group}"
        policy = policy_key
        group  = group
      }
    ]
  ])
}

resource "databricks_instance_pool" "shared" {
  instance_pool_name                    = var.instance_pool_name
  node_type_id                          = var.pool_node_type_id
  min_idle_instances                    = var.pool_min_idle_instances
  max_capacity                          = var.pool_max_capacity
  idle_instance_autotermination_minutes = var.pool_idle_autotermination_minutes
  preloaded_spark_versions              = [var.spark_version]

  azure_attributes {
    availability       = var.pool_availability
    spot_bid_max_price = -1
  }

  custom_tags = {
    CostCentre  = var.cost_centre
    Environment = var.environment
  }
}

resource "databricks_cluster_policy" "this" {
  for_each = local.policies

  name                  = each.value.name
  description           = each.value.description
  definition            = jsonencode(each.value.definition)
  max_clusters_per_user = each.value.max_per_user
}

resource "databricks_permissions" "policy_usage" {
  for_each = { for p in local.policy_user_pairs : p.policy => p.group... }

  cluster_policy_id = databricks_cluster_policy.this[each.key].id

  dynamic "access_control" {
    for_each = toset(each.value)

    content {
      group_name       = access_control.value
      permission_level = "CAN_USE"
    }
  }
}
