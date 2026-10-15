-- ============================================================================
-- Data quality queries (Spark SQL) - the same checks the Python validator
-- runs, expressed in SQL for Databricks SQL alerts and ad-hoc investigation.
-- ============================================================================
USE CATALOG dataplatform_dev;

-- 1. Uniqueness: duplicate business keys in silver (should always be zero rows).
SELECT claim_id, COUNT(*) AS versions
FROM silver.claims
GROUP BY claim_id
HAVING COUNT(*) > 1;

-- 2. Completeness: null rate per critical column in one scan.
SELECT
  COUNT(*)                                                  AS rows,
  ROUND(AVG(CASE WHEN claim_id      IS NULL THEN 1 ELSE 0 END) * 100, 3) AS pct_null_claim_id,
  ROUND(AVG(CASE WHEN policy_number IS NULL THEN 1 ELSE 0 END) * 100, 3) AS pct_null_policy_number,
  ROUND(AVG(CASE WHEN claim_date    IS NULL THEN 1 ELSE 0 END) * 100, 3) AS pct_null_claim_date,
  ROUND(AVG(CASE WHEN claim_amount  IS NULL THEN 1 ELSE 0 END) * 100, 3) AS pct_null_claim_amount
FROM silver.claims;

-- 3. Validity: accepted values, regex and range violations with sample offenders.
SELECT 'claim_type'    AS column_name, claim_type    AS offending_value, COUNT(*) AS n
FROM silver.claims
WHERE claim_type NOT IN ('motor', 'home', 'health', 'life', 'travel', 'UNKNOWN')
GROUP BY claim_type
UNION ALL
SELECT 'policy_number', policy_number, COUNT(*)
FROM silver.claims
WHERE policy_number NOT RLIKE '^POL-[0-9]{6}$'
GROUP BY policy_number
UNION ALL
SELECT 'claim_amount', CAST(claim_amount AS STRING), COUNT(*)
FROM silver.claims
WHERE claim_amount < 0 OR claim_amount > 5000000
GROUP BY claim_amount
ORDER BY n DESC
LIMIT 50;

-- 4. Referential integrity: claims whose policy is unknown.
SELECT c.claim_id, c.policy_number, c.claim_date
FROM silver.claims c
LEFT ANTI JOIN silver.policies p ON p.policy_number = c.policy_number;

-- 5. Freshness: hours since the latest silver load per dataset (alert if > 48).
SELECT 'claims'   AS dataset, MAX(_processed_at) AS latest, ROUND((UNIX_TIMESTAMP() - UNIX_TIMESTAMP(MAX(_processed_at))) / 3600, 1) AS hours_old FROM silver.claims
UNION ALL
SELECT 'policies', MAX(_processed_at), ROUND((UNIX_TIMESTAMP() - UNIX_TIMESTAMP(MAX(_processed_at))) / 3600, 1) FROM silver.policies;

-- 6. Volume anomaly: today's bronze landings vs the trailing 14-day median.
WITH daily AS (
  SELECT CAST(_ingested_at AS DATE) AS d, COUNT(*) AS rows
  FROM bronze.claims
  WHERE _ingested_at >= CURRENT_DATE() - INTERVAL 15 DAYS
  GROUP BY 1
),
baseline AS (
  SELECT PERCENTILE_APPROX(rows, 0.5) AS median_rows FROM daily WHERE d < CURRENT_DATE()
)
SELECT
  d,
  rows,
  median_rows,
  ROUND(rows / NULLIF(median_rows, 0), 2) AS ratio_to_median,
  CASE WHEN rows < median_rows * 0.5 OR rows > median_rows * 2 THEN 'ANOMALY' ELSE 'ok' END AS verdict
FROM daily CROSS JOIN baseline
WHERE d = CURRENT_DATE();

-- 7. Quarantine triage: what is failing, by rule and source file.
SELECT
  _ingest_run_id,
  _source_file,
  COALESCE(rule, 'parse_error') AS rule,
  COUNT(*)                      AS rows
FROM quarantine.claims
LATERAL VIEW OUTER EXPLODE(_dq_failed_rules) r AS rule
WHERE _ingested_at >= CURRENT_DATE() - INTERVAL 7 DAYS
GROUP BY 1, 2, 3
ORDER BY rows DESC;

-- 8. SCD2 invariants on the customer dimension.
--    a) exactly one current row per key
SELECT customer_id, COUNT(*) AS current_rows
FROM gold.dim_customers
WHERE is_current
GROUP BY customer_id
HAVING COUNT(*) <> 1;
--    b) no overlapping or gapped versions
SELECT customer_id, effective_from, effective_to, next_from
FROM (
  SELECT customer_id, effective_from, effective_to,
         LEAD(effective_from) OVER (PARTITION BY customer_id ORDER BY effective_from) AS next_from
  FROM gold.dim_customers
)
WHERE effective_to IS NOT NULL AND effective_to <> next_from;

-- 9. Reconciliation: bronze -> silver -> gold row and value totals for one run.
WITH b AS (SELECT COUNT(DISTINCT claim_id) AS keys, SUM(claim_amount) AS amount FROM bronze.claims),
     s AS (SELECT COUNT(*) AS keys, SUM(claim_amount) AS amount FROM silver.claims),
     g AS (SELECT SUM(volume) AS keys, SUM(total_value) AS amount FROM gold.claims_monthly_trends)
SELECT 'bronze_distinct_keys' AS layer, b.keys, b.amount FROM b
UNION ALL SELECT 'silver', s.keys, s.amount FROM s
UNION ALL SELECT 'gold_monthly', g.keys, g.amount FROM g;

-- 10. Change Data Feed: what changed in silver since a given version (incremental consumers).
SELECT _change_type, COUNT(*) AS rows
FROM table_changes('silver.claims', 10)
GROUP BY _change_type;
