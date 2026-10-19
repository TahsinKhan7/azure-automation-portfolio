# resource-group

**What this demonstrates:** a resource group that carries its own governance: tags, an optional `CanNotDelete`/`ReadOnly` management lock, and a monthly consumption budget with actual and forecasted spend notifications.

## Structure

| File | Purpose |
|------|---------|
| `main.tf` | Resource group, lock and budget with dynamic threshold notifications |
| `variables.tf` | Lock level, budget amount/start/thresholds/contacts, all validated |
| `outputs.tf` | IDs for the group, lock and budget |
| `versions.tf` | Terraform and provider version constraints |

## Usage

```hcl
module "resource_group" {
  source                = "../../modules/resource-group"
  name                  = module.naming.resource_group
  location              = "uksouth"
  lock_level            = "CanNotDelete"
  budget_amount         = 2500
  budget_contact_emails = ["dataplatform-alerts@example.com"]
  tags                  = local.common_tags
}
```

Validate on its own with `terraform -chdir=terraform/modules/resource-group init -backend=false && terraform -chdir=terraform/modules/resource-group validate`.

## Design decisions

- Budgets sit at resource-group scope so cost ownership matches the RBAC and lifecycle boundary.
- The budget `end_date` is ignored in `lifecycle` because the portal rewrites it and would otherwise produce a permanent diff.
- The lock is deliberately optional and defaults to none so that short-lived environments can be destroyed by the pipeline; upper environments enable it in tfvars.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Resource group name. | `string` | n/a | yes |
| `location` | Azure region. | `string` | `uksouth` | no |
| `tags` | Tags applied to the resource group. | `map(string)` | `{}` | no |
| `lock_level` | Management lock applied to the resource group. null disables the lock; CanNotDelete is recommended for preprod and prod. | `string` | `null` | no |
| `budget_amount` | Monthly budget in the billing currency. null disables the consumption budget. | `number` | `null` | no |
| `budget_start_date` | Budget period start in RFC 3339 format. Must be the first day of a month and no earlier than the current month. | `string` | `2026-11-01T00:00:00Z` | no |
| `budget_thresholds` | Percentages of the budget at which actual spend notifications are sent. | `list(number)` | `[50, 80, 100]` | no |
| `budget_forecast_threshold` | Percentage of the budget at which a forecasted-spend notification is sent. | `number` | `110` | no |
| `budget_contact_emails` | Email addresses notified when a budget threshold is reached. | `list(string)` | `[]` | no |
| `budget_action_group_ids` | Optional action group resource IDs invoked when a threshold is reached. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Resource group resource ID. |
| `name` | Resource group name. |
| `location` | Resource group location. |
| `lock_id` | Management lock ID, or null when no lock is configured. |
| `budget_id` | Consumption budget ID, or null when no budget is configured. |
