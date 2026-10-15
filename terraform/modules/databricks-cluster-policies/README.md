# databricks-cluster-policies

**What this demonstrates:** cost control as code for Databricks: a shared instance pool and three cluster policies (job, shared interactive, single-node) that pin auto-termination, approved SKUs, worker caps, runtime and mandatory cost tags, with `CAN_USE` permissions per group.

## Structure

| File | Purpose |
|------|---------|
| `main.tf` | Policy definitions as HCL (rendered with `jsonencode`), instance pool, permissions |
| `variables.tf` | Pool sizing and availability, SKU allow-list, caps, policy user map |
| `outputs.tf` | Pool ID and policy IDs/names |
| `versions.tf` | Terraform and provider version constraints |

## Usage

```hcl
module "databricks_cluster_policies" {
  source             = "../../modules/databricks-cluster-policies"
  environment        = var.environment
  cost_centre        = "CC-DATA-PROD"
  instance_pool_name = module.naming.databricks_instance_pool
  pool_availability  = "ON_DEMAND_AZURE"
  max_workers        = 16
  policy_users = {
    job         = ["data-engineers"]
    shared      = ["data-analysts"]
    single_node = ["data-scientists"]
  }
}
```

Validate on its own with `terraform -chdir=terraform/modules/databricks-cluster-policies init -backend=false && terraform -chdir=terraform/modules/databricks-cluster-policies validate`.

## Design decisions

- Policies are written as HCL maps and `jsonencode`d, so they are diffable, variable-driven and never contain copy-pasted JSON.
- `custom_tags.CostCentre` and `custom_tags.Environment` are fixed in every policy, which is what makes the Databricks cost export attributable without manual tagging.
- Pools do not support spot-with-fallback, so availability is a validated variable: spot in lower environments, on-demand where job SLAs matter.
- The job policy pins the pool and Photon; interactive policies allow a SKU list and a bounded auto-termination range rather than a single value, leaving users some choice within guard-rails.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `environment` | Environment name, embedded in policy names and enforced as a cluster tag. | `string` | n/a | yes |
| `cost_centre` | Cost centre tag value every policy forces onto clusters. | `string` | n/a | yes |
| `instance_pool_name` | Name of the shared instance pool. | `string` | n/a | yes |
| `pool_node_type_id` | VM SKU of the pooled instances. | `string` | `Standard_DS3_v2` | no |
| `pool_max_capacity` | Upper bound on pooled instances (idle plus in use). Caps spend from runaway autoscaling. | `number` | `20` | no |
| `pool_min_idle_instances` | Warm instances kept ready. 0 in lower environments; a small number in prod shortens job start-up. | `number` | `0` | no |
| `pool_availability` | Capacity type of pooled instances. SPOT_AZURE is cheaper but may be evicted; use ON_DEMAND_AZURE for production SLAs. Pools do not support spot-with-fallback. | `string` | `SPOT_AZURE` | no |
| `pool_idle_autotermination_minutes` | Minutes an idle pooled instance survives before release. | `number` | `15` | no |
| `spark_version` | Databricks Runtime pinned for pooled instances and allowed by policies. Use an LTS version. | `string` | `15.4.x-scala2.12` | no |
| `allowed_node_type_ids` | VM SKUs that interactive clusters may use. | `list(string)` | `[Standard_DS3_v2, Standard_DS4_v2, Standard_E4ds_v5, Stan...` | no |
| `max_workers` | Maximum autoscale workers for job and shared clusters. | `number` | `8` | no |
| `interactive_autotermination_minutes` | Maximum idle minutes before an interactive cluster terminates. | `number` | `60` | no |
| `policy_users` | Map of policy key (job, shared, single_node) to the groups allowed to use it. | `map(list(string))` | `{job: [data-engineers], shared: [data-engineers, data-ana...` | no |
| `max_clusters_per_user` | Maximum clusters a single user may create from the interactive policies. | `number` | `2` | no |

## Outputs

| Name | Description |
|------|-------------|
| `instance_pool_id` | ID of the shared instance pool. |
| `policy_ids` | Map of policy key (job, shared, single_node) to cluster policy ID. Pass the job policy ID to Data Factory and Workflows. |
| `policy_names` | Map of policy key to policy display name. |
