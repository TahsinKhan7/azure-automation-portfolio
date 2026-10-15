-- ============================================================================
-- Delta table DDL for the dataplatform lakehouse (dev shown; swap the catalog)
-- Demonstrates: liquid clustering vs partitioning, table properties for
-- auto-compaction / CDF / retention, column comments, generated columns,
-- constraints, and external vs managed tables.
-- ============================================================================
USE CATALOG dataplatform_dev;

-- ---------------------------------------------------------------------------
-- BRONZE: external, append-only, partitioned by ingest date for cheap retention
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.claims (
  claim_id        STRING        COMMENT 'Source claim identifier (not yet de-duplicated)',
  policy_number   STRING        COMMENT 'Policy reference, format POL-nnnnnn',
  claim_date      DATE          COMMENT 'Date the claim was raised',
  claim_type      STRING        COMMENT 'motor | home | health | life | travel (uncleaned)',
  claim_amount    DECIMAL(18,2) COMMENT 'Claimed amount in GBP',
  business_unit   STRING,
  status          STRING,
  claimant_name   STRING        COMMENT 'PII - masked outside the engineers group',
  _ingested_at    TIMESTAMP     COMMENT 'When the row landed in bronze',
  _source_file    STRING        COMMENT 'Originating file path for lineage/replay',
  _ingest_run_id  STRING        COMMENT 'Run identifier shared with the quarantine table',
  _dataset        STRING,
  _ingest_date    DATE GENERATED ALWAYS AS (CAST(_ingested_at AS DATE)) COMMENT 'Partition key'
)
USING DELTA
PARTITIONED BY (_ingest_date)
LOCATION 'abfss://bronze@stdataplatformdev.dfs.core.windows.net/claims/'
COMMENT 'Raw claims as landed. Append only; never updated in place.'
TBLPROPERTIES (
  'quality' = 'bronze',
  'delta.appendOnly' = 'true',
  'delta.autoOptimize.optimizeWrite' = 'true',
  'delta.autoOptimize.autoCompact' = 'true',
  'delta.logRetentionDuration' = 'interval 90 days',
  'delta.deletedFileRetentionDuration' = 'interval 30 days'
);

-- ---------------------------------------------------------------------------
-- QUARANTINE: same shape as bronze plus the raw record and failure reason
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS quarantine.claims (
  _corrupt_record   STRING    COMMENT 'Raw text of the row that failed to parse',
  _dq_failed_rules  ARRAY<STRING> COMMENT 'Rule names that rejected the row (row-level DQ)',
  _ingested_at      TIMESTAMP,
  _source_file      STRING,
  _ingest_run_id    STRING,
  _dataset          STRING,
  _quarantined_at   TIMESTAMP
)
USING DELTA
LOCATION 'abfss://quarantine@stdataplatformdev.dfs.core.windows.net/claims/'
COMMENT 'Rows rejected by parsing or row-level data quality rules, retained for triage and replay.'
TBLPROPERTIES ('quality' = 'quarantine', 'delta.logRetentionDuration' = 'interval 30 days');

-- ---------------------------------------------------------------------------
-- SILVER: liquid clustering on the usual filter columns (no partition skew,
-- no small-file explosion from high-cardinality keys), CDF on for downstream
-- incremental consumers, constraints to enforce the contract.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.claims (
  claim_id        STRING        NOT NULL COMMENT 'Business key; exactly one row per claim',
  policy_number   STRING        NOT NULL,
  claim_date      DATE          NOT NULL,
  claim_type      STRING        COMMENT 'Lower-cased, UNKNOWN when missing',
  claim_amount    DECIMAL(18,2) COMMENT 'Non-negative by constraint',
  business_unit   STRING,
  status          STRING,
  claimant_name   STRING,
  year            INT           COMMENT 'Derived from claim_date',
  month           INT,
  year_month      STRING,
  _ingested_at    TIMESTAMP,
  _processed_at   TIMESTAMP     COMMENT 'Silver conformance time (freshness checks use this)',
  _etl_version    STRING,
  _run_id         STRING,
  CONSTRAINT pk_claims PRIMARY KEY (claim_id) NOT ENFORCED
)
USING DELTA
CLUSTER BY (claim_date, policy_number)
LOCATION 'abfss://silver@stdataplatformdev.dfs.core.windows.net/claims/'
COMMENT 'Conformed claims. One row per claim_id (latest by _ingested_at).'
TBLPROPERTIES (
  'quality' = 'silver',
  'delta.enableChangeDataFeed' = 'true',
  'delta.autoOptimize.optimizeWrite' = 'true',
  'delta.autoOptimize.autoCompact' = 'true',
  'delta.columnMapping.mode' = 'name',          -- allows column rename/drop without rewrite
  'delta.minReaderVersion' = '2',
  'delta.minWriterVersion' = '5',
  'delta.logRetentionDuration' = 'interval 30 days',
  'delta.deletedFileRetentionDuration' = 'interval 7 days'
);

ALTER TABLE silver.claims ADD CONSTRAINT claim_amount_non_negative CHECK (claim_amount >= 0);
ALTER TABLE silver.claims ADD CONSTRAINT claim_type_known
  CHECK (claim_type IN ('motor', 'home', 'health', 'life', 'travel', 'UNKNOWN'));
ALTER TABLE silver.claims ALTER COLUMN claimant_name SET MASK silver.mask_name;

CREATE TABLE IF NOT EXISTS silver.policies (
  policy_number   STRING        NOT NULL,
  customer_id     STRING        NOT NULL,
  product         STRING,
  start_date      DATE          NOT NULL,
  end_date        DATE,
  annual_premium  DECIMAL(18,2),
  status          STRING,
  year            INT,
  _processed_at   TIMESTAMP,
  _etl_version    STRING,
  _run_id         STRING,
  CONSTRAINT pk_policies PRIMARY KEY (policy_number) NOT ENFORCED
)
USING DELTA
CLUSTER BY (policy_number, customer_id)
LOCATION 'abfss://silver@stdataplatformdev.dfs.core.windows.net/policies/'
TBLPROPERTIES ('quality' = 'silver', 'delta.enableChangeDataFeed' = 'true');

ALTER TABLE silver.policies ADD CONSTRAINT policy_dates_ordered CHECK (end_date IS NULL OR end_date >= start_date);

-- Informational FK for lineage tools and the DQ referential-integrity check.
ALTER TABLE silver.claims ADD CONSTRAINT fk_claims_policy
  FOREIGN KEY (policy_number) REFERENCES silver.policies(policy_number) NOT ENFORCED;

-- ---------------------------------------------------------------------------
-- GOLD: SCD2 dimension and monthly fact. Dimension clusters on the business
-- key + current flag because every lookup filters on them.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gold.dim_customers (
  customer_id     STRING    NOT NULL,
  full_name       STRING,
  email           STRING,
  postcode        STRING,
  segment         STRING,
  _hash_diff      STRING    COMMENT 'SHA-256 of tracked columns; drives change detection',
  effective_from  TIMESTAMP NOT NULL COMMENT 'Version valid from (inclusive)',
  effective_to    TIMESTAMP COMMENT 'Version valid to (exclusive); NULL for the current row',
  is_current      BOOLEAN   NOT NULL
)
USING DELTA
CLUSTER BY (customer_id, is_current)
LOCATION 'abfss://gold@stdataplatformdev.dfs.core.windows.net/dim_customers/'
COMMENT 'Customer dimension, SCD Type 2. Join facts on customer_id with effective_from <= event_ts < coalesce(effective_to, timestamp ''9999-12-31'').'
TBLPROPERTIES ('quality' = 'gold', 'delta.enableChangeDataFeed' = 'true');

CREATE TABLE IF NOT EXISTS gold.claims_monthly_trends (
  year_month      STRING        NOT NULL,
  business_unit   STRING,
  volume          BIGINT,
  total_value     DECIMAL(28,2),
  avg_value       DECIMAL(22,6),
  previous_value  DECIMAL(28,2),
  mom_change      DECIMAL(28,2),
  mom_change_pct  DECIMAL(10,2) COMMENT 'NULL for the first month and when the previous month is zero',
  rolling_avg_3   DECIMAL(28,4) COMMENT 'Trailing three-month average of total_value',
  _aggregated_at  TIMESTAMP,
  _run_id         STRING
)
USING DELTA
CLUSTER BY (year_month)
LOCATION 'abfss://gold@stdataplatformdev.dfs.core.windows.net/claims/monthly_trends/'
TBLPROPERTIES ('quality' = 'gold');

-- Managed ops table for DQ results written by the quality gate notebook.
CREATE TABLE IF NOT EXISTS ops.dq_check_results (
  environment   STRING,
  dataset       STRING,
  layer         STRING,
  validated_at  TIMESTAMP,
  name          STRING,
  check_type    STRING,
  passed        BOOLEAN,
  checked       BIGINT,
  failed        BIGINT,
  details       STRING,
  severity      STRING
)
USING DELTA
PARTITIONED BY (environment)
COMMENT 'One row per data quality check per run; feeds the DQ trend dashboard.';

-- Switch an existing partitioned table to liquid clustering without a rewrite of history:
-- ALTER TABLE silver.claims CLUSTER BY (claim_date, policy_number);
-- OPTIMIZE silver.claims;   -- incremental re-clustering of unclustered files only
