-- ============================================================================
-- Gold KPI views for Databricks SQL / Power BI
-- Thin, documented views over gold tables so BI tools never query silver
-- directly and metric definitions live in one place.
-- ============================================================================
USE CATALOG dataplatform_dev;

-- Current customer only (the most common dimension join).
CREATE OR REPLACE VIEW gold.v_dim_customers_current
  COMMENT 'Current version of each customer from the SCD2 dimension'
AS
SELECT customer_id, full_name, email, postcode, segment, effective_from
FROM gold.dim_customers
WHERE is_current;

-- Point-in-time customer attributes for a claim (SCD2 join pattern).
CREATE OR REPLACE VIEW gold.v_claims_with_customer_asof
  COMMENT 'Claims joined to the customer version that was valid on the claim date'
AS
SELECT
  c.claim_id,
  c.claim_date,
  c.claim_type,
  c.claim_amount,
  c.business_unit,
  p.customer_id,
  d.segment            AS customer_segment_at_claim,
  d.postcode           AS customer_postcode_at_claim
FROM silver.claims  AS c
JOIN silver.policies AS p ON p.policy_number = c.policy_number
LEFT JOIN gold.dim_customers AS d
  ON d.customer_id = p.customer_id
 AND CAST(c.claim_date AS TIMESTAMP) >= d.effective_from
 AND CAST(c.claim_date AS TIMESTAMP) <  COALESCE(d.effective_to, TIMESTAMP '9999-12-31 00:00:00');

-- Monthly KPI tile source: latest 24 months, with YoY alongside MoM.
CREATE OR REPLACE VIEW gold.v_claims_monthly_kpis
  COMMENT 'Monthly claims KPIs with month-on-month and year-on-year change'
AS
WITH base AS (
  SELECT
    year_month,
    business_unit,
    volume,
    total_value,
    avg_value,
    mom_change_pct,
    rolling_avg_3,
    LAG(total_value, 12) OVER (PARTITION BY business_unit ORDER BY year_month) AS same_month_last_year
  FROM gold.claims_monthly_trends
)
SELECT
  year_month,
  business_unit,
  volume,
  total_value,
  avg_value,
  mom_change_pct,
  rolling_avg_3,
  same_month_last_year,
  CASE WHEN same_month_last_year > 0
       THEN ROUND((total_value - same_month_last_year) / same_month_last_year * 100, 2)
  END AS yoy_change_pct
FROM base
WHERE year_month >= DATE_FORMAT(ADD_MONTHS(CURRENT_DATE(), -24), 'yyyy-MM');

-- Claim frequency and severity by product line (classic insurance KPIs).
CREATE OR REPLACE VIEW gold.v_claims_frequency_severity
  COMMENT 'Claims per 100 active policies (frequency) and average claim cost (severity) by product and month'
AS
WITH policies_active AS (
  SELECT
    DATE_FORMAT(m.month_start, 'yyyy-MM') AS year_month,
    p.product,
    COUNT(*)                              AS active_policies
  FROM silver.policies p
  JOIN (
    SELECT EXPLODE(SEQUENCE(TRUNC(ADD_MONTHS(CURRENT_DATE(), -24), 'MM'), TRUNC(CURRENT_DATE(), 'MM'), INTERVAL 1 MONTH)) AS month_start
  ) m
    ON p.start_date <= LAST_DAY(m.month_start)
   AND COALESCE(p.end_date, DATE '9999-12-31') >= m.month_start
  GROUP BY 1, 2
),
claims_month AS (
  SELECT
    c.year_month,
    p.product,
    COUNT(*)            AS claim_count,
    SUM(c.claim_amount) AS claim_cost
  FROM silver.claims c
  JOIN silver.policies p ON p.policy_number = c.policy_number
  GROUP BY 1, 2
)
SELECT
  a.year_month,
  a.product,
  a.active_policies,
  COALESCE(cm.claim_count, 0)                                          AS claim_count,
  ROUND(COALESCE(cm.claim_count, 0) / a.active_policies * 100, 3)      AS frequency_per_100,
  ROUND(cm.claim_cost / NULLIF(cm.claim_count, 0), 2)                  AS severity_avg_cost,
  ROUND(COALESCE(cm.claim_cost, 0) / a.active_policies, 2)             AS burning_cost_per_policy
FROM policies_active a
LEFT JOIN claims_month cm ON cm.year_month = a.year_month AND cm.product = a.product;

-- Open claims ageing buckets for operations dashboards.
CREATE OR REPLACE VIEW gold.v_open_claims_ageing
  COMMENT 'Open claims bucketed by age in days'
AS
SELECT
  business_unit,
  claim_type,
  CASE
    WHEN DATEDIFF(CURRENT_DATE(), claim_date) <= 30  THEN '0-30'
    WHEN DATEDIFF(CURRENT_DATE(), claim_date) <= 60  THEN '31-60'
    WHEN DATEDIFF(CURRENT_DATE(), claim_date) <= 90  THEN '61-90'
    ELSE '90+'
  END                                   AS age_bucket,
  COUNT(*)                              AS open_claims,
  SUM(claim_amount)                     AS open_amount,
  PERCENTILE_APPROX(claim_amount, 0.5)  AS median_amount
FROM silver.claims
WHERE status = 'open'
GROUP BY 1, 2, 3;

-- Data quality trend for the platform health dashboard.
CREATE OR REPLACE VIEW ops.v_dq_pass_rate_daily
  COMMENT 'Daily pass rate of data quality checks per dataset'
AS
SELECT
  CAST(validated_at AS DATE)                                    AS check_date,
  dataset,
  layer,
  COUNT(*)                                                      AS checks,
  SUM(CASE WHEN passed THEN 1 ELSE 0 END)                       AS passed,
  SUM(CASE WHEN NOT passed AND severity = 'error' THEN 1 ELSE 0 END) AS blocking_failures,
  ROUND(SUM(CASE WHEN passed THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS pass_rate_pct
FROM ops.dq_check_results
GROUP BY 1, 2, 3;
