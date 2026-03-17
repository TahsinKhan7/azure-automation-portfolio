"""
Silver to Gold ETL Pipeline
Aggregates cleansed silver-layer data into business-ready datasets
for analytics, reporting and Power BI consumption.
"""

from pyspark.sql import SparkSession, DataFrame
from pyspark.sql import functions as F
from datetime import datetime


def get_spark():
    return (
        SparkSession.builder
        .appName("silver-to-gold-etl")
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog")
        .getOrCreate()
    )


def build_daily_summary(df, date_col, group_cols, value_col):
    """Aggregate daily metrics for operational dashboards."""
    return (
        df
        .withColumn("report_date", F.to_date(F.col(date_col)))
        .groupBy(["report_date"] + group_cols)
        .agg(
            F.count("*").alias("record_count"),
            F.sum(value_col).alias("total_value"),
            F.avg(value_col).alias("avg_value"),
            F.min(value_col).alias("min_value"),
            F.max(value_col).alias("max_value"),
            F.stddev(value_col).alias("stddev_value")
        )
        .withColumn("_aggregated_at", F.current_timestamp())
    )


def build_monthly_trends(df, date_col, category_col, value_col):
    """Month-over-month trend analysis for executive reporting."""
    monthly = (
        df
        .withColumn("year_month", F.date_format(F.col(date_col), "yyyy-MM"))
        .groupBy("year_month", category_col)
        .agg(
            F.count("*").alias("volume"),
            F.sum(value_col).alias("total_value"),
            F.avg(value_col).alias("avg_value")
        )
        .orderBy("year_month", category_col)
    )

    # Add month-over-month change
    from pyspark.sql.window import Window
    w = Window.partitionBy(category_col).orderBy("year_month")
    monthly = monthly.withColumn("prev_total", F.lag("total_value").over(w))
    monthly = monthly.withColumn(
        "mom_change_pct",
        F.when(F.col("prev_total") > 0,
               F.round((F.col("total_value") - F.col("prev_total")) / F.col("prev_total") * 100, 2))
    ).drop("prev_total")

    return monthly


def build_kpi_snapshot(df, date_col, value_col):
    """Build a single-row KPI snapshot for dashboard cards."""
    return df.agg(
        F.count("*").alias("total_records"),
        F.sum(value_col).alias("total_value"),
        F.avg(value_col).alias("average_value"),
        F.min(date_col).alias("earliest_record"),
        F.max(date_col).alias("latest_record"),
        F.countDistinct("business_unit").alias("business_units")
    ).withColumn("_snapshot_at", F.current_timestamp())


def write_gold(df, target_path):
    df.write.format("delta").mode("overwrite").save(target_path)
    print(f"  Written to gold: {target_path} ({df.count()} records)")


def run_silver_to_gold(silver_path, gold_base_path):
    print(f"\n{'='*60}")
    print(f"Silver -> Gold ETL | {datetime.now().isoformat()}")
    print(f"{'='*60}\n")

    spark = get_spark()
    df = spark.read.format("delta").load(silver_path)

    daily = build_daily_summary(df, "claim_date", ["business_unit", "claim_type"], "claim_amount")
    write_gold(daily, f"{gold_base_path}/daily_summary/")

    monthly = build_monthly_trends(df, "claim_date", "business_unit", "claim_amount")
    write_gold(monthly, f"{gold_base_path}/monthly_trends/")

    kpi = build_kpi_snapshot(df, "claim_date", "claim_amount")
    write_gold(kpi, f"{gold_base_path}/kpi_snapshot/")

    print(f"\nCompleted: {datetime.now().isoformat()}")


if __name__ == "__main__":
    run_silver_to_gold(
        silver_path="abfss://silver@datalake.dfs.core.windows.net/claims/cleansed/",
        gold_base_path="abfss://gold@datalake.dfs.core.windows.net/claims/"
    )
