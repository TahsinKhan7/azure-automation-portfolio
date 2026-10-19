# ADR 0001: Medallion layers on Delta Lake with a data quality gate

Status: accepted

## Context

Source data arrives as database extracts and file drops of varying quality. Consumers need conformed, trustworthy tables for KPIs and a slowly changing customer dimension, and auditors need to know where every row came from. Schema inference across files is non-deterministic and silently widens types; bad records must not break a run or corrupt curated data.

## Decision

Organise ADLS Gen2 into `landing`, `bronze`, `silver` and `gold` containers with Delta tables registered in Unity Catalog, plus a `quarantine` area. Bronze is append-only with an explicit DDL per dataset and PERMISSIVE parsing that routes malformed rows to quarantine with their raw text. Silver holds one typed row per business key. A data quality gate driven by YAML expectation suites sits between silver and gold and raises `DataQualityError` on blocking failures, so gold is never written from data that failed. SCD Type 2 dimensions use hash-diff change detection and a single atomic Delta `MERGE`. Bronze is partitioned by ingest date; silver and gold use liquid clustering.

Implementation: [`python/src/dataplatform/etl`](../../python/src/dataplatform/etl/), [`python/src/dataplatform/quality`](../../python/src/dataplatform/quality/), [`sql/databricks-sql/delta_table_ddl.sql`](../../sql/databricks-sql/delta_table_ddl.sql).

## Consequences

- Replay and retention are simple: bronze keeps the raw history, landing expires, gold can be rebuilt from silver.
- Transforms are pure DataFrame functions, so the whole pipeline is unit-tested on a local Spark session.
- A blocking quality failure stops the job rather than producing a report nobody reads; `warn`-severity rules still surface without blocking.
- Quarantine needs an owner and a triage view ([`data_quality_queries.sql`](../../sql/databricks-sql/data_quality_queries.sql) provides one); without it, bad rows accumulate silently.
- Delta-specific features (MERGE, change data feed, liquid clustering, VACUUM retention) tie the design to Delta Lake, which is acceptable for an Azure Databricks platform.
