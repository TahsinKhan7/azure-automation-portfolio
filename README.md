# Azure Automation Portfolio

A collection of production-style scripts, templates and modules for Azure DevOps, Data Engineering and Cloud Platform operations. Built from real-world experience managing enterprise Azure environments — CI/CD pipelines, Databricks platform administration, ETL pipeline engineering, infrastructure as code, and platform monitoring.

## Contents

| Folder | Description | Files |
|--------|-------------|-------|
| [powershell/](./powershell/) | Automation scripts for Azure AD, Databricks API, Key Vault, Storage, Power BI and cost management | 15 |
| [terraform/](./terraform/) | Reusable IaC modules for Databricks, Storage, Key Vault, Networking with multi-environment support | 14 |
| [python/](./python/) | PySpark ETL pipelines (medallion architecture), data quality framework, Databricks cluster & Unity Catalog management | 7 |
| [azure-devops-pipelines/](./azure-devops-pipelines/) | YAML pipeline templates for CI/CD, Databricks deployments, Terraform IaC, ADF ARM deployment | 6 |
| [arm-bicep/](./arm-bicep/) | Bicep templates for Databricks, Data Factory, Storage, Key Vault, Networking, SQL, Monitoring, Log Analytics | 9 |
| [kql-queries/](./kql-queries/) | Log Analytics and Azure Monitor queries for alerting, health monitoring and cost anomaly detection | 4 |
| [sql/](./sql/) | Azure SQL scripts for staging schemas, pipeline metadata, monitoring views and maintenance procedures | 5 |
| [kubernetes/](./kubernetes/) | AKS manifests for deployments, ingress, autoscaling, secrets and monitoring | 6 |

## Tech Stack

- **Cloud:** Microsoft Azure (PaaS & IaaS)
- **DevOps:** Azure DevOps (Repos, Pipelines, Boards, Artifacts), YAML pipelines, Git
- **IaC:** Terraform, ARM Templates, Bicep
- **Scripting:** PowerShell, Python, Bash, KQL
- **Data:** Azure Databricks (PySpark, Unity Catalog, Delta Lake), Azure Data Factory, ADLS Gen2, Azure SQL, Power BI
- **Security:** Azure AD / Entra ID, Key Vault, RBAC, Azure Policy, Conditional Access
- **Monitoring:** Azure Monitor, Log Analytics, KQL alerting
- **Containers:** Docker, Kubernetes (AKS)

## Structure

```
azure-automation-portfolio/
├── powershell/
│   ├── azure-ad/           # AD group management, RBAC, user sync
│   ├── databricks-api/     # Token rotation, Unity Catalog, job management
│   ├── storage/            # Data Lake ACLs, Key Vault audit, storage compliance
│   └── powerbi/            # Workspace management, gateway refresh
├── terraform/
│   ├── modules/            # Databricks, Storage, Key Vault, Networking
│   └── environments/       # Dev and Prod tfvars
├── python/
│   ├── etl/                # Bronze-to-Silver, Silver-to-Gold (PySpark)
│   └── databricks/         # Cluster manager, ADF monitor, data quality, Unity Catalog
├── azure-devops-pipelines/ # CI, CD, Databricks deploy, Terraform, ADF deploy
├── arm-bicep/              # 8 Bicep templates covering full data platform
├── kql-queries/            # Pipeline alerts, resource health, cost anomalies
├── sql/                    # Staging schemas, metadata tables, monitoring views
└── kubernetes/             # AKS deployments, ingress, HPA, secrets
```

## Author

**Tahsin Khan** — Azure DevOps & Data Engineer | [LinkedIn](https://linkedin.com/in/tahsinkhan4)
