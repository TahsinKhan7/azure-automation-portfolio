# ------------------------------------------------------------------------------
# Resource group with optional management lock and monthly consumption budget.
#
# Budgets are created at the resource-group scope so that cost ownership
# follows the same boundary as RBAC and lifecycle. Thresholds send email and
# (optionally) action-group notifications; nothing is enforced automatically.
# ------------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = var.name
  location = var.location
  tags     = var.tags
}

resource "azurerm_management_lock" "this" {
  count = var.lock_level != null ? 1 : 0

  name       = "lock-${var.name}"
  scope      = azurerm_resource_group.this.id
  lock_level = var.lock_level
  notes      = "Managed by Terraform. Remove the lock through the pipeline, not the portal."
}

resource "azurerm_consumption_budget_resource_group" "this" {
  count = var.budget_amount != null ? 1 : 0

  name              = "bud-${var.name}"
  resource_group_id = azurerm_resource_group.this.id
  amount            = var.budget_amount
  time_grain        = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  dynamic "notification" {
    for_each = toset([for t in var.budget_thresholds : tostring(t)])

    content {
      enabled        = true
      threshold      = tonumber(notification.value)
      operator       = "GreaterThanOrEqualTo"
      threshold_type = "Actual"

      contact_emails = var.budget_contact_emails
      contact_groups = var.budget_action_group_ids
    }
  }

  notification {
    enabled        = true
    threshold      = var.budget_forecast_threshold
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Forecasted"

    contact_emails = var.budget_contact_emails
    contact_groups = var.budget_action_group_ids
  }

  lifecycle {
    # The portal rewrites time_period.end_date; ignoring it prevents perpetual diffs.
    ignore_changes = [time_period[0].end_date]
  }
}
