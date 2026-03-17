# SQL Scripts

Database scripts for Azure SQL operations — schema management, data pipeline support tables, monitoring views and maintenance procedures.

| Script | Purpose |
|--------|---------|
| `create_pipeline_metadata_tables.sql` | Metadata tables for tracking ETL pipeline runs and data lineage |
| `create_staging_schema.sql` | Staging area schema for ADF landing zone with merge procedures |
| `monitoring_views.sql` | Views for database health, query performance and blocking analysis |
| `maintenance_procedures.sql` | Index rebuilds, statistics updates and partition management |

## Usage

Execute against Azure SQL Database using Azure Data Studio, SSMS or `sqlcmd`:

```bash
sqlcmd -S sql-prod-001.database.windows.net -d OperationsDB -U admin -P $PASSWORD -i create_pipeline_metadata_tables.sql
```
