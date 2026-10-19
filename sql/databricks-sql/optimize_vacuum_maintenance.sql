-- ============================================================================
-- Delta Lake maintenance (Spark SQL)
-- Weekly housekeeping for the lakehouse; the Python runner
-- (dataplatform.databricks.delta_maintenance) renders these same statements
-- behind an allow-list and dry-run switch.
-- ============================================================================
USE CATALOG dataplatform_dev;

-- ---------------------------------------------------------------------------
-- 0. Before: file counts and sizes so the effect of OPTIMIZE is measurable.
-- ---------------------------------------------------------------------------
DESCRIBE DETAIL silver.claims;
DESCRIBE DETAIL gold.dim_customers;

-- ---------------------------------------------------------------------------
-- 1. OPTIMIZE
--    Liquid-clustered tables: plain OPTIMIZE re-clusters incrementally.
--    Partitioned / unclustered tables: ZORDER BY the common filter columns.
--    Restrict to recent partitions on large partitioned tables.
-- ---------------------------------------------------------------------------
OPTIMIZE silver.claims;                                   -- CLUSTER BY (claim_date, policy_number)
OPTIMIZE silver.policies;                                 -- CLUSTER BY (policy_number, customer_id)
OPTIMIZE gold.dim_customers;                              -- CLUSTER BY (customer_id, is_current)
OPTIMIZE gold.claims_monthly_trends;

OPTIMIZE bronze.claims
  WHERE _ingest_date >= CURRENT_DATE() - INTERVAL 7 DAYS  -- only the partitions still receiving files
  ZORDER BY (claim_id);

-- ---------------------------------------------------------------------------
-- 2. VACUUM
--    Default retention is 7 days (168 hours). Shorter retention breaks time
--    travel and any reader still holding an old snapshot; the platform keeps
--    the safety check enabled and uses longer retention in prod.
-- ---------------------------------------------------------------------------
VACUUM silver.claims              RETAIN 168 HOURS;
VACUUM silver.policies            RETAIN 168 HOURS;
VACUUM gold.dim_customers         RETAIN 336 HOURS;       -- dimension history is queried with time travel
VACUUM gold.claims_monthly_trends RETAIN 168 HOURS;
VACUUM bronze.claims              RETAIN 720 HOURS;       -- 30 days: replay window for re-processing

-- Preview what VACUUM would remove without deleting anything.
VACUUM silver.claims RETAIN 168 HOURS DRY RUN;

-- ---------------------------------------------------------------------------
-- 3. Table history and metrics (audit what maintenance did).
-- ---------------------------------------------------------------------------
SELECT version, timestamp, operation, operationMetrics
FROM (DESCRIBE HISTORY silver.claims)
WHERE operation IN ('OPTIMIZE', 'VACUUM END', 'VACUUM START')
ORDER BY version DESC
LIMIT 20;

-- Files added/removed by the last OPTIMIZE.
SELECT
  timestamp,
  operationMetrics.numRemovedFiles AS files_removed,
  operationMetrics.numAddedFiles   AS files_added,
  operationMetrics.numRemovedBytes AS bytes_removed,
  operationMetrics.numAddedBytes   AS bytes_added
FROM (DESCRIBE HISTORY silver.claims)
WHERE operation = 'OPTIMIZE'
ORDER BY version DESC
LIMIT 1;

-- ---------------------------------------------------------------------------
-- 4. Statistics and clustering changes
-- ---------------------------------------------------------------------------
ANALYZE TABLE silver.claims COMPUTE STATISTICS FOR ALL COLUMNS;

-- Move a legacy partitioned table to liquid clustering (metadata-only, then
-- incremental OPTIMIZE re-clusters files over subsequent runs).
-- ALTER TABLE gold.claims_daily_summary CLUSTER BY (report_date, business_unit);
-- OPTIMIZE gold.claims_daily_summary;

-- Enable predictive optimisation to let the platform schedule OPTIMIZE/VACUUM
-- automatically for managed tables (Unity Catalog, account-level feature).
-- ALTER CATALOG dataplatform_dev ENABLE PREDICTIVE OPTIMIZATION;

-- ---------------------------------------------------------------------------
-- 5. Small-file check across the catalog: candidates for OPTIMIZE.
-- ---------------------------------------------------------------------------
-- Run per table; DESCRIBE DETAIL returns numFiles and sizeInBytes.
SELECT
  name,
  numFiles,
  ROUND(sizeInBytes / 1024 / 1024, 1)                 AS size_mb,
  ROUND(sizeInBytes / NULLIF(numFiles, 0) / 1024 / 1024, 2) AS avg_file_mb,
  CASE WHEN numFiles > 50 AND sizeInBytes / NULLIF(numFiles, 0) < 32 * 1024 * 1024
       THEN 'OPTIMIZE recommended' ELSE 'ok' END     AS verdict
FROM (DESCRIBE DETAIL silver.claims);
