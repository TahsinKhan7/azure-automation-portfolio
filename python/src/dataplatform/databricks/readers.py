"""Readers for the Azure data sources the platform ingests from.

Credentials for JDBC sources are passed in, never read from code; on Databricks they come
from a secret scope backed by Key Vault.
"""

from __future__ import annotations

import logging
from collections.abc import Iterable

from pyspark.sql import DataFrame, SparkSession

logger = logging.getLogger(__name__)


def adls_uri(storage_account: str, container: str, path: str = "") -> str:
    """Build an ``abfss://`` URI."""
    return f"abfss://{container}@{storage_account}.dfs.core.windows.net/{path.lstrip('/')}"


def read_adls(
    spark: SparkSession,
    storage_account: str,
    container: str,
    path: str,
    fmt: str = "parquet",
    schema: str | None = None,
    **options: str,
) -> DataFrame:
    """Read files from ADLS Gen2 in the given format, with an optional DDL schema."""
    uri = adls_uri(storage_account, container, path)
    logger.info("Reading %s from %s", fmt, uri)
    reader = spark.read.format(fmt).options(**options)
    if schema:
        reader = reader.schema(schema)
    return reader.load(uri)


def read_delta(
    spark: SparkSession, path: str, version: int | None = None, timestamp: str | None = None
) -> DataFrame:
    """Read a Delta table by path with optional time travel."""
    if version is not None and timestamp is not None:
        raise ValueError("Specify version or timestamp, not both")
    reader = spark.read.format("delta")
    if version is not None:
        reader = reader.option("versionAsOf", version)
    elif timestamp is not None:
        reader = reader.option("timestampAsOf", timestamp)
    logger.info("Reading delta %s (version=%s, timestamp=%s)", path, version, timestamp)
    return reader.load(path)


def read_uc_table(spark: SparkSession, catalog: str, schema: str, table: str) -> DataFrame:
    """Read a Unity Catalog table by its three-part name."""
    fqn = f"{catalog}.{schema}.{table}"
    logger.info("Reading table %s", fqn)
    return spark.table(fqn)


def azure_sql_jdbc_url(server: str, database: str) -> str:
    return (
        f"jdbc:sqlserver://{server}.database.windows.net:1433;database={database};"
        "encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;"
        "loginTimeout=30;"
    )


def read_azure_sql(
    spark: SparkSession,
    server: str,
    database: str,
    username: str,
    password: str,
    table: str | None = None,
    query: str | None = None,
    fetch_size: int = 10_000,
) -> DataFrame:
    """Read a table or query from Azure SQL Database over JDBC."""
    if bool(table) == bool(query):
        raise ValueError("Provide exactly one of table or query")
    reader = (
        spark.read.format("jdbc")
        .option("url", azure_sql_jdbc_url(server, database))
        .option("user", username)
        .option("password", password)
        .option("fetchsize", str(fetch_size))
        .option("driver", "com.microsoft.sqlserver.jdbc.SQLServerDriver")
    )
    reader = reader.option("dbtable", table) if table else reader.option("query", query)
    logger.info("Reading Azure SQL %s/%s (%s)", server, database, table or "query")
    return reader.load()


def require_columns(df: DataFrame, expected: Iterable[str]) -> DataFrame:
    """Return ``df`` unchanged or raise ``ValueError`` listing the missing columns."""
    missing = sorted(set(expected) - set(df.columns))
    if missing:
        raise ValueError(f"Missing columns: {missing}")
    return df
