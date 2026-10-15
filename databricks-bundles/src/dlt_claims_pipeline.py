# Databricks notebook source
# MAGIC %md
# MAGIC # Claims - Delta Live Tables pipeline
# MAGIC Declarative bronze -> silver -> gold for claims with expectations at each hop.
# MAGIC `@dlt.expect_or_drop` quarantines bad rows (visible in the pipeline event log),
# MAGIC `@dlt.expect_or_fail` stops the update on contract violations.

# COMMAND ----------

import dlt
from pyspark.sql import functions as F
from pyspark.sql.window import Window

landing_path = spark.conf.get("dataplatform.landing_path")
environment = spark.conf.get("dataplatform.environment", "dev")

CLAIMS_SCHEMA = (
    "claim_id STRING, policy_number STRING, claim_date DATE, claim_type STRING, "
    "claim_amount DECIMAL(18,2), business_unit STRING, status STRING, claimant_name STRING, "
    "_rescued_data STRING"
)

# COMMAND ----------


@dlt.table(
    name="bronze_claims",
    comment="Raw claims as landed; schema enforced, unparseable columns kept in _rescued_data.",
    table_properties={"quality": "bronze", "pipelines.reset.allowed": "false"},
)
def bronze_claims():
    return (
        spark.readStream.format("cloudFiles")
        .option("cloudFiles.format", "csv")
        .option("cloudFiles.rescuedDataColumn", "_rescued_data")
        .option("header", "true")
        .schema(CLAIMS_SCHEMA)
        .load(landing_path)
        .withColumn("_ingested_at", F.current_timestamp())
        .withColumn("_source_file", F.col("_metadata.file_path"))
    )


# COMMAND ----------


@dlt.table(
    name="silver_claims",
    comment="Conformed claims: one row per claim_id, typed, with period columns.",
    table_properties={"quality": "silver", "delta.enableChangeDataFeed": "true"},
    partition_cols=["year"],
)
@dlt.expect_or_drop("valid_claim_id", "claim_id IS NOT NULL")
@dlt.expect_or_drop("valid_policy_number", "policy_number RLIKE '^POL-[0-9]{6}$'")
@dlt.expect_or_drop("non_negative_amount", "claim_amount >= 0")
@dlt.expect("known_claim_type", "claim_type IN ('motor','home','health','life','travel')")
@dlt.expect_or_fail("no_rescued_data", "_rescued_data IS NULL")
def silver_claims():
    latest = Window.partitionBy("claim_id").orderBy(F.col("_ingested_at").desc())
    return (
        dlt.read("bronze_claims")
        .withColumn("claim_type", F.lower(F.trim("claim_type")))
        .withColumn("business_unit", F.coalesce(F.trim("business_unit"), F.lit("UNKNOWN")))
        .withColumn("_rn", F.row_number().over(latest))
        .filter(F.col("_rn") == 1)
        .drop("_rn")
        .withColumn("year", F.year("claim_date"))
        .withColumn("month", F.month("claim_date"))
        .withColumn("_processed_at", F.current_timestamp())
    )


# COMMAND ----------


@dlt.table(
    name="gold_claims_monthly",
    comment="Monthly claim volume and value by business unit with month-on-month change.",
    table_properties={"quality": "gold"},
)
@dlt.expect_or_fail("positive_volume", "volume > 0")
def gold_claims_monthly():
    monthly = (
        dlt.read("silver_claims")
        .withColumn("year_month", F.date_format("claim_date", "yyyy-MM"))
        .groupBy("year_month", "business_unit")
        .agg(
            F.count(F.lit(1)).alias("volume"),
            F.sum("claim_amount").alias("total_value"),
            F.avg("claim_amount").alias("avg_value"),
        )
    )
    trend = Window.partitionBy("business_unit").orderBy("year_month")
    previous = F.col("previous_value")
    change_pct = F.round((F.col("total_value") - previous) / previous * 100, 2)
    return monthly.withColumn("previous_value", F.lag("total_value").over(trend)).withColumn(
        "mom_change_pct", F.when(previous > 0, change_pct)
    )
