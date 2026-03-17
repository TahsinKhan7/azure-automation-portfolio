# Python Scripts

PySpark ETL pipelines (medallion architecture), data quality validation, Databricks management and Azure Data Factory monitoring utilities.

## ETL Pipelines (`etl/`)

| Script | Purpose |
|--------|---------|
| `etl_bronze_to_silver.py` | Raw data cleansing, deduplication and standardisation (bronze → silver) |
| `etl_silver_to_gold.py` | Business-ready aggregations with MoM trends and KPI snapshots (silver → gold) |

## Databricks Utilities (`databricks/`)

| Script | Purpose |
|--------|---------|
| `databricks_cluster_manager.py` | Cluster lifecycle management, idle detection and cost optimisation |
| `adf_pipeline_monitor.py` | Monitor ADF pipeline runs, failure rates and long-running jobs |
| `data_quality_checks.py` | Reusable quality validation framework (null checks, uniqueness, freshness) |
| `read_data_sources.py` | PySpark readers for ADLS, Delta Lake, Azure SQL, Unity Catalog and Blob Storage |
| `unity_catalog_manager.py` | Manage catalogs, schemas, tables and permissions via REST API |

## Requirements

- Python 3.9+
- PySpark (included in Databricks Runtime)
- `requests`, `azure-identity`, `azure-mgmt-datafactory` for standalone scripts
