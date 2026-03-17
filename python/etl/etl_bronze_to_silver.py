"""
Bronze to Silver ETL Pipeline
Reads raw data from the bronze layer, applies cleansing, deduplication
and schema standardisation, then writes to the silver layer in Delta format.
"""

from pyspark.sql import SparkSession, DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import StringType
from datetime import datetime


def get_spark():
    return (
        SparkSession.builder
        .appName("bronze-to-silver-etl")
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog")
        .getOrCreate()
    )


def read_bronze(spark, source_path, file_format="parquet"):
    print(f"Reading bronze data from: {source_path}")
    df = spark.read.format(file_format).load(source_path)
    print(f"  Records read: {df.count()}")
    return df


def clean_column_names(df):
    for col_name in df.columns:
        clean = col_name.strip().lower().replace(" ", "_").replace("-", "_")
        df = df.withColumnRenamed(col_name, clean)
    return df


def remove_duplicates(df, key_columns):
    if "_ingested_at" in df.columns:
        from pyspark.sql.window import Window
        window = Window.partitionBy(key_columns).orderBy(F.col("_ingested_at").desc())
        df = df.withColumn("_rn", F.row_number().over(window))
        df = df.filter(F.col("_rn") == 1).drop("_rn")
    else:
        df = df.dropDuplicates(key_columns)
    return df


def apply_null_handling(df, default="UNKNOWN"):
    string_cols = [f.name for f in df.schema.fields if isinstance(f.dataType, StringType)]
    for col_name in string_cols:
        df = df.withColumn(col_name, F.coalesce(F.col(col_name), F.lit(default)))
    return df


def add_audit_columns(df):
    return (
        df
        .withColumn("_processed_at", F.current_timestamp())
        .withColumn("_source_file", F.input_file_name())
        .withColumn("_etl_version", F.lit("1.0"))
    )


def write_silver(df, target_path, partition_cols=None):
    writer = df.write.format("delta").mode("overwrite")
    if partition_cols:
        writer = writer.partitionBy(partition_cols)
    writer.save(target_path)
    print(f"  Written to silver: {target_path} ({df.count()} records)")


def run_bronze_to_silver(source_path, target_path, key_columns, partition_cols=None):
    print(f"\n{'='*60}")
    print(f"Bronze -> Silver ETL | {datetime.now().isoformat()}")
    print(f"{'='*60}\n")

    spark = get_spark()
    df = read_bronze(spark, source_path)
    df = clean_column_names(df)
    df = remove_duplicates(df, key_columns)
    df = apply_null_handling(df)
    df = add_audit_columns(df)
    write_silver(df, target_path, partition_cols)

    print(f"\nCompleted: {datetime.now().isoformat()}")


if __name__ == "__main__":
    run_bronze_to_silver(
        source_path="abfss://bronze@datalake.dfs.core.windows.net/claims/raw/",
        target_path="abfss://silver@datalake.dfs.core.windows.net/claims/cleansed/",
        key_columns=["claim_id", "policy_number"],
        partition_cols=["year", "month"]
    )
