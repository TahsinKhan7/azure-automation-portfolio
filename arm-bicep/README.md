# ARM / Bicep templates

**What this demonstrates:** the same data platform as `../terraform`, expressed in Bicep for teams standardised on native Azure deployments: one composition template (`main.bicep`) with an `@allowed` environment parameter and a per-environment sizing map, eight resource templates that each stand alone, `.bicepparam` files per environment, a linter configuration enforced at build time, and secrets resolved from Key Vault at deployment time rather than stored in parameters.

## Structure

| File | Deploys |
|------|---------|
| `main.bicep` | Composition: naming, environment sizing profile, all modules below, outputs for the pipeline |
| `log-analytics.bicep` | Log Analytics workspace, retention and daily cap, VM Insights and Key Vault Analytics solutions, Activity Log DCR |
| `networking.bicep` | VNet with delegated Databricks subnets, NSG, private endpoint subnet |
| `key-vault.bicep` | Key Vault with access policies, soft delete, purge protection, firewall, audit diagnostics |
| `storage-account.bicep` | ADLS Gen2 account, medallion containers, soft delete, lifecycle tiering |
| `databricks-workspace.bicep` | Premium VNet-injected workspace with secure cluster connectivity and diagnostics |
| `data-factory.bicep` | Data Factory with Key Vault, ADLS, Databricks and (optional) SQL linked services |
| `sql-database.bicep` | Azure SQL server and database with Entra admin, auditing and diagnostics |
| `monitoring-alerts.bicep` | Scheduled query alerts: ADF failures, Databricks job failures, error rate, Key Vault denials, storage throttling |
| `parameters/main.<env>.bicepparam` | Environment parameter files for dev, ite, iqe, preprod and prod |
| `bicepconfig.json` | Linter rules (security rules at `error`, hygiene rules at `warning`) and formatting |

## How to run

```bash
# Validate and lint every template (what CI runs)
for f in arm-bicep/*.bicep; do bicep build "$f" --stdout > /dev/null; done
for p in arm-bicep/parameters/*.bicepparam; do bicep build-params "$p" --stdout > /dev/null; done

# Preview a deployment
az deployment group what-if \
  --resource-group rg-dp-data-dev-uks-01 \
  --parameters arm-bicep/parameters/main.dev.bicepparam

# Deploy
az deployment group create \
  --resource-group rg-dp-data-dev-uks-01 \
  --parameters arm-bicep/parameters/main.dev.bicepparam

# Deploy a single template on its own
az deployment group create \
  --resource-group rg-dp-data-dev-uks-01 \
  --template-file arm-bicep/key-vault.bicep \
  --parameters keyVaultName=kv-dp-data-dev-01 adminObjectId=<object id>
```

The resource group itself is created by the pipeline (or by `../powershell/New-AzureResourceGroup.ps1`) because `main.bicep` is scoped to a resource group; keeping the group outside the template lets the delete lock and budget be managed independently of the workload deployment.

## Design decisions

- **Environment as data.** `main.bicep` holds an `envConfig` map keyed by the `@allowed` environment value. Retention, storage SKU, soft-delete days, SQL tier and address space all come from that map, so the five parameter files contain only identities, allow-lists and tags.
- **Names match Terraform.** The naming variables reproduce `terraform/modules/naming`, so a Key Vault referenced by the AKS manifests resolves to the same name whichever toolchain deployed it.
- **No secrets in parameters.** `sqlAdminPassword` is `@secure()` with no default and is resolved with `getSecret()` from a platform vault inside the `.bicepparam` file, which is the only place Bicep allows it.
- **Conditional modules.** SQL and alert rules deploy only when `deploySql` or `actionGroupId` say so; the Data Factory SQL linked service follows the same condition.
- **Lint at build.** `bicepconfig.json` sets the secret-handling rules to `error` so a `bicep build` in CI fails on hard-coded URLs, insecure parameter defaults or secrets in outputs. `use-recent-api-versions` is off because API versions are pinned deliberately and reviewed on a schedule, not on every build; `what-if-short-circuiting` is off because passing module outputs (workspace IDs, resource names) between modules is the purpose of the composition and the reduced what-if precision is accepted.
- **Small fixes to the original templates.** Single-line objects now use comma separators (the only syntax Bicep accepts), the Key Vault access-policy loop is declared as a variable before `concat()`, and the previously unused `databricksWorkspaceId` parameter now drives a Databricks job-failure alert.

## Requirements

- Bicep CLI 0.30 or later (safe-dereference `[?]` and `??` are used in `main.bicep`)
- Azure CLI 2.60 or later
- Contributor on the target resource group and Key Vault Secrets User on the platform vault referenced by `getSecret()`
