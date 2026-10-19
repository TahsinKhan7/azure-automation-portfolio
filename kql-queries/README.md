# KQL queries

**What this demonstrates:** Log Analytics / Azure Monitor queries used for alerting, workbooks and governance reporting across the data platform: Data Factory reliability and latency trends, Databricks cluster governance and cost, Key Vault secret hygiene, resource health and spend anomalies. Each file begins with a header stating the purpose, the source table(s) and the schema it relies on, so a reader can tell at a glance whether the query applies to their workspace.

## Queries

| File | Source tables | Purpose |
|------|---------------|---------|
| `pipeline-failure-alerts.kql` | `ADFPipelineRun`, `ADFActivityRun`, `ADFTriggerRun` | Failed runs, failure rate by hour, activity-level errors, long runners, trigger failures |
| `adf-pipeline-run-duration-trends.kql` | `ADFPipelineRun` | Daily percentiles, week-over-baseline slowdown detection, trend slope, SLA breaches, variance |
| `databricks-cluster-events.kql` | `DatabricksClusters` | Lifecycle volume, clusters created without a policy, long-running interactive clusters, failed starts, top creators |
| `key-vault-secret-near-expiry.kql` | `KeyVaultSecretInventory_CL`, `AzureDiagnostics` | Expiring or expired secrets prioritised by recent use, secrets with no expiry, vault summary, alert query |
| `resource-health-dashboard.kql` | `Heartbeat`, `AzureActivity`, `StorageBlobLogs`, `AzureDiagnostics`, NSG flow logs | Platform health tiles across compute, storage, Key Vault and networking |
| `cost-anomaly-detection.kql` | `AzureActivity`, `StorageBlobLogs`, `Usage` | Deployment spikes, compute-heavy provisioning, storage growth, daily spend anomalies |

## How to use

- **Alert rules:** sections marked as alert queries (for example section 4 in the Key Vault file) return a count; create a scheduled query rule with `Count > 0`. The Bicep template `arm-bicep/monitoring-alerts.bicep` shows the wiring.
- **Workbooks:** sections that end with `by bin(...)` or `make-series` are intended for time charts; the rest render as grids.
- **Grafana:** the Azure Monitor data source accepts the same KQL; replace `ago(30d)` with `$__timeFilter(TimeGenerated)` where a dashboard time picker is wanted.
- **Prerequisites:** the Terraform modules in `../terraform` enable the diagnostic categories these queries read (resource-specific tables for ADF and Databricks, `AuditEvent` for Key Vault). The secret inventory table is produced by `../powershell/storage/Export-KeyVaultSecrets.ps1`.

## Conventions

- Each file starts with a header comment: purpose, source table(s), schema used, intended usage.
- Sections are numbered and self-contained; each is runnable on its own.
- Time windows are explicit (`ago(7d)`) so a copied query behaves predictably in an alert rule.
- Thresholds that encode policy (SLA minutes, warning days) sit in a `let` or `datatable` at the top of the section so they are reviewable in pull requests.
