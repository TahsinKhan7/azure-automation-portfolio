# SQL

Two families of SQL live here: **T-SQL for Azure SQL Database** (the operational and
metadata side of the platform) and **Spark SQL for Databricks / Unity Catalog** (the
lakehouse side). Together they show governance, metadata-driven ingestion, Delta table
design, KPI modelling and maintenance.

## What it demonstrates

- Metadata-driven ADF ingestion: control tables, watermarks advanced transactionally with the
  run log, and a health view for alerting (`azure-sql/metadata_driven_pipeline_config.sql`).
- Unity Catalog governance: catalog / schema layout, least-privilege grants per role, external
  locations and a column mask (`databricks-sql/create_unity_catalog_objects.sql`).
- Delta table design: liquid clustering vs partitioning, generated columns, constraints,
  change data feed, retention properties, column comments (`databricks-sql/delta_table_ddl.sql`).
- Insurance-style KPIs in SQL: MoM / YoY change, frequency and severity, SCD2 as-of joins
  (`databricks-sql/gold_kpi_views.sql`).
- Data quality and reconciliation queries mirroring the Python validator
  (`databricks-sql/data_quality_queries.sql`).
- OPTIMIZE / ZORDER / VACUUM with measurable before/after
  (`databricks-sql/optimize_vacuum_maintenance.sql`).

## Files

| File | Engine | What it shows |
|------|--------|---------------|
| `create_pipeline_metadata_tables.sql` | Azure SQL | `meta` schema: pipeline run tracking, DQ results, lineage and watermark tables |
| `create_staging_schema.sql` | Azure SQL | Staging landing tables for ADF with MERGE-based upsert procedures |
| `monitoring_views.sql` | Azure SQL | Pipeline success rates, DQ dashboard, blocking and query-performance views |
| `maintenance_procedures.sql` | Azure SQL | Index rebuild by fragmentation, statistics refresh, partition and retention management |
| `azure-sql/metadata_driven_pipeline_config.sql` | Azure SQL | `ctl` schema: source systems, per-dataset ingestion config, watermarks, run log, the stored procedures a generic ADF Lookup/ForEach/Copy pipeline calls, a health view and idempotent seed data |
| `databricks-sql/create_unity_catalog_objects.sql` | Spark SQL | Storage credential, external location, catalog, layer schemas, volume, role-based grants, column mask function |
| `databricks-sql/delta_table_ddl.sql` | Spark SQL | Bronze / quarantine / silver / gold / ops DDL with clustering, partitioning, constraints, CDF and retention properties |
| `databricks-sql/gold_kpi_views.sql` | Spark SQL | Current-customer view, SCD2 as-of join, monthly KPIs with MoM and YoY, frequency/severity, ageing buckets, DQ pass-rate trend |
| `databricks-sql/data_quality_queries.sql` | Spark SQL | Uniqueness, completeness, validity, referential integrity, freshness, volume anomaly, quarantine triage, SCD2 invariants, reconciliation, CDF |
| `databricks-sql/optimize_vacuum_maintenance.sql` | Spark SQL | OPTIMIZE (incremental for liquid clustering, ZORDER for partitioned), VACUUM with safe retention, history metrics, small-file check |

## How to run

Azure SQL (T-SQL): execute with Azure Data Studio, SSMS or `sqlcmd`. Scripts are idempotent
(`IF OBJECT_ID ... IS NULL`, `CREATE OR ALTER`, `MERGE` seeds) so they can be re-run safely
from a deployment pipeline.

```bash
sqlcmd -S sql-dataplatform-dev.database.windows.net -d dataplatform_ops -G \
       -i azure-sql/metadata_driven_pipeline_config.sql
```

Databricks (Spark SQL): run in a Databricks SQL warehouse or notebook with a Unity Catalog
enabled workspace. Each file starts with `USE CATALOG dataplatform_dev;` - change the suffix
to target another environment. `create_unity_catalog_objects.sql` requires metastore admin or
catalog owner privileges; the rest run as the pipeline service principal.

## Design decisions

- **Metadata over pipelines.** A new source table is one row in `ctl.IngestionConfig`; the
  ADF pipeline is generic. Watermarks move only inside the same transaction that marks the run
  succeeded, so a failed copy can never skip a window.
- **Layered grants.** Permissions are granted at schema level so new tables inherit them;
  analysts never see bronze or quarantine, which may hold raw PII.
- **Liquid clustering for silver and gold, partitions for bronze.** Bronze is partitioned by
  ingest date because retention and replay are date driven; silver and gold cluster on the
  columns users actually filter on, avoiding partition skew and small files.
- **Constraints as documentation that executes.** `CHECK` constraints and informational
  primary/foreign keys encode the same contract the Python expectation suites test.
- **Safe maintenance defaults.** VACUUM retention never drops below 7 days in these scripts;
  bronze keeps 30 days to preserve the re-processing window.
