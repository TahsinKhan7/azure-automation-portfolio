# Environment: dev

**What this demonstrates:** one of five environment roots that share an identical `main.tf`, `variables.tf`, `versions.tf` and `outputs.tf`; everything specific to `dev` is data in `terraform.tfvars` and the state key in `backend.tf`.

Lowest-cost sandbox for feature work. Public endpoints behind firewall rules, spot instance pool, 30-day logs with a daily cap, purge protection off so the vault can be rebuilt, and the only Git-connected Data Factory. Nightly destroy/recreate is acceptable; no lock.

## Structure

| File | Purpose |
|------|---------|
| `main.tf` | Composes the modules in `../../modules` (identical across environments; verify with `md5sum ../*/main.tf`) |
| `variables.tf` | Root inputs with safe, low-cost defaults (identical across environments) |
| `terraform.tfvars` | The `dev` values: SKUs, retention, network ranges, toggles, grants |
| `versions.tf` | Provider requirements and provider configuration (OIDC-driven, no identifiers committed) |
| `backend.tf` | azurerm backend with key `dataplatform/dev.tfstate`; the storage account is overridden by the pipeline |
| `outputs.tf` | Values consumed by the ADF, Databricks and AKS pipelines |

## How to run

```bash
cd terraform/environments/dev
terraform init \
  -backend-config="storage_account_name=<state account>" \
  -backend-config="resource_group_name=<state resource group>"
terraform plan -out=tfplan
terraform apply tfplan
```

In CI the same steps run with `ARM_USE_OIDC=true` and the environment's service connection; see `../../README.md` for the promotion order and approvals.

## Design decisions

- Nothing in this folder except `terraform.tfvars` and the backend key should ever differ from the other environments. If a change needs to be environment-specific, add a variable.
- `environment` has no default on purpose: a plan cannot run without the tfvars, which prevents applying one environment's values to another by mistake.
- Placeholders (`00000000-...`, `203.0.113.x`, `example.com`) stand in for object IDs, allow-listed IPs and contacts; the pipeline supplies real values from variable groups.
