# ARM & Bicep Templates

Infrastructure as Code templates for deploying Azure resources using Bicep (compiled to ARM). Covers the core data platform stack: Databricks, Data Factory, storage, networking, monitoring and security.

| Template | Resources Deployed |
|----------|--------------------|
| `databricks-workspace.bicep` | Databricks workspace with VNet injection and diagnostics |
| `data-factory.bicep` | Data Factory with linked services (ADLS, Databricks, SQL) |
| `storage-account.bicep` | ADLS Gen2 storage with medallion containers and lifecycle policies |
| `key-vault.bicep` | Key Vault with access policies and diagnostic logging |
| `monitoring-alerts.bicep` | Azure Monitor alert rules for pipeline failures and resource health |
| `networking.bicep` | VNet with Databricks subnets, NSGs and private endpoints |
| `log-analytics.bicep` | Log Analytics workspace with retention and data collection rules |
| `sql-database.bicep` | Azure SQL Database with firewall rules and auditing |

## Deployment

```bash
# Deploy a single template
az deployment group create \
  --resource-group rg-data-prod \
  --template-file databricks-workspace.bicep \
  --parameters @parameters/prod.json

# Deploy all resources via main orchestrator
az deployment group create \
  --resource-group rg-data-prod \
  --template-file main.bicep \
  --parameters environment=prod location=uksouth
```
