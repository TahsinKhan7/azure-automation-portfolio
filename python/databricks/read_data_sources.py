"""
Data Source Readers
PySpark utilities for reading data from various Azure data sources into Databricks.
Supports ADLS, Azure SQL, Blob Storage, CSV/Parquet/JSON and Delta Lake.
"""

from pyspark.sql import SparkSession, DataFrame
from pyspark.sql import functions as F


def get_spark():
    return SparkSession.builder.appName("data-source-readers").getOrCreate()


# ============================================================
# ADLS Gen2 (Data Lake)
# ============================================================

def read_adls_parquet(spark, storage_account, container, path):
    """Read Parquet files from ADLS Gen2."""
    uri = f"abfss://{container}@{storage_account}.dfs.core.windows.net/{path}"
    print(f"Reading ADLS Parquet: {uri}")
    return spark.read.format("parquet").load(uri)


def read_adls_csv(spark, storage_account, container, path, header=True, delimiter=","):
    """Read CSV files from ADLS Gen2 with schema inference."""
    uri = f"abfss://{container}@{storage_account}.dfs.core.windows.net/{path}"
    print(f"Reading ADLS CSV: {uri}")
    return (
        spark.read.format("csv")
        .option("header", header)
        .option("delimiter", delimiter)
        .option("inferSchema", True)
        .load(uri)
    )


def read_adls_json(spark, storage_account, container, path, multiline=False):
    """Read JSON files from ADLS Gen2."""
    uri = f"abfss://{container}@{storage_account}.dfs.core.windows.net/{path}"
    print(f"Reading ADLS JSON: {uri}")
    return spark.read.format("json").option("multiLine", multiline).load(uri)


# ============================================================
# Delta Lake
# ============================================================

def read_delta(spark, path, version=None, timestamp=None):
    """Read Delta Lake table with optional time travel."""
    reader = spark.read.format("delta")
    if version is not None:
        reader = reader.option("versionAsOf", version)
    elif timestamp:
        reader = reader.option("timestampAsOf", timestamp)
    print(f"Reading Delta: {path} (version={version}, timestamp={timestamp})")
    return reader.load(path)


def read_unity_catalog_table(spark, catalog, schema, table):
    """Read a table registered in Unity Catalog."""
    fqn = f"{catalog}.{schema}.{table}"
    print(f"Reading Unity Catalog: {fqn}")
    return spark.table(fqn)


# ============================================================
# Azure SQL Database
# ============================================================

def read_azure_sql(spark, server, database, table, username, password):
    """Read table from Azure SQL Database via JDBC."""
    jdbc_url = f"jdbc:sqlserver://{server}.database.windows.net:1433;database={database}"
    print(f"Reading Azure SQL: {server}/{database}/{table}")
    return (
        spark.read.format("jdbc")
        .option("url", jdbc_url)
        .option("dbtable", table)
        .option("user", username)
        .option("password", password)
        .option("encrypt", "true")
        .option("trustServerCertificate", "false")
        .option("hostNameInCertificate", "*.database.windows.net")
        .load()
    )


def read_azure_sql_query(spark, server, database, query, username, password):
    """Read custom SQL query results from Azure SQL Database."""
    jdbc_url = f"jdbc:sqlserver://{server}.database.windows.net:1433;database={database}"
    print(f"Reading Azure SQL query: {server}/{database}")
    return (
        spark.read.format("jdbc")
        .option("url", jdbc_url)
        .option("query", query)
        .option("user", username)
        .option("password", password)
        .option("encrypt", "true")
        .load()
    )


# ============================================================
# Azure Blob Storage (legacy)
# ============================================================

def read_blob_parquet(spark, storage_account, container, path):
    """Read Parquet from Azure Blob Storage (wasbs)."""
    uri = f"wasbs://{container}@{storage_account}.blob.core.windows.net/{path}"
    print(f"Reading Blob Parquet: {uri}")
    return spark.read.format("parquet").load(uri)


# ============================================================
# Utility: Schema validation after read
# ============================================================

def validate_schema(df, expected_columns):
    """Validate that a DataFrame contains all expected columns."""
    actual = set(df.columns)
    expected = set(expected_columns)
    missing = expected - actual
    if missing:
        raise ValueError(f"Missing columns: {missing}")
    print(f"  Schema valid: {len(expected)} expected columns present")
    return df


# ============================================================
# Usage examples
# ============================================================

if __name__ == "__main__":
    spark = get_spark()

    # ADLS Gen2 - medallion layers
    bronze_df = read_adls_parquet(spark, "stproddatalake001", "bronze", "claims/raw/")
    silver_df = read_delta(spark, "abfss://silver@stproddatalake001.dfs.core.windows.net/claims/")

    # Delta time travel - read yesterday's snapshot
    historical = read_delta(spark, "abfss://silver@stproddatalake001.dfs.core.windows.net/claims/",
                            timestamp="2025-01-15T00:00:00Z")

    # Unity Catalog
    gold_df = read_unity_catalog_table(spark, "enterprise_data", "gold", "daily_claims_summary")

    # Azure SQL
    sql_df = read_azure_sql(spark, "sql-prod-001", "OperationsDB", "dbo.PolicyMaster",
                            username="reader_svc", password="from-key-vault")

    # Validate schemas
    validate_schema(bronze_df, ["claim_id", "policy_number", "claim_date", "claim_amount"])
