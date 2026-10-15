"""Delta-enabled SparkSession factory.

On Databricks the session already exists and carries Delta support, so ``get_spark`` simply
returns it. Locally (unit tests, developer laptops, CI) it builds a single-JVM session with
the Delta Lake extension wired in via ``delta-spark``.
"""

from __future__ import annotations

import logging
import os
import sys
import tempfile
from collections.abc import Mapping

from pyspark.sql import SparkSession
from pyspark.sql.types import StructType

logger = logging.getLogger(__name__)

DELTA_CONF: Mapping[str, str] = {
    "spark.sql.extensions": "io.delta.sql.DeltaSparkSessionExtension",
    "spark.sql.catalog.spark_catalog": "org.apache.spark.sql.delta.catalog.DeltaCatalog",
}

LOCAL_CONF: Mapping[str, str] = {
    "spark.ui.enabled": "false",
    "spark.ui.showConsoleProgress": "false",
    "spark.sql.shuffle.partitions": "4",
    "spark.default.parallelism": "4",
    "spark.sql.session.timeZone": "UTC",
    "spark.databricks.delta.retentionDurationCheck.enabled": "false",
    "spark.driver.extraJavaOptions": "-Dlog4j2.level=error",
}


def is_databricks_runtime() -> bool:
    """True when running inside a Databricks cluster."""
    return "DATABRICKS_RUNTIME_VERSION" in os.environ


def get_spark(
    app_name: str = "dataplatform",
    local: bool = False,
    extra_conf: Mapping[str, str] | None = None,
    warehouse_dir: str | None = None,
) -> SparkSession:
    """Return a Delta-enabled SparkSession.

    Args:
        app_name: Spark application name (ignored when the session already exists).
        local: Build a ``local[2]`` session with Delta JARs resolved through ``delta-spark``.
            Use this for tests and local development.
        extra_conf: Additional Spark configuration applied last (highest precedence).
        warehouse_dir: Optional warehouse directory for local sessions.
    """
    builder = SparkSession.builder.appName(app_name)
    for key, value in DELTA_CONF.items():
        builder = builder.config(key, value)

    if local:
        # Workers must run the same interpreter as the driver; without this PySpark falls
        # back to whatever `python3` resolves to on PATH.
        os.environ.setdefault("PYSPARK_PYTHON", sys.executable)
        os.environ.setdefault("PYSPARK_DRIVER_PYTHON", sys.executable)
        builder = builder.master("local[2]")
        for key, value in LOCAL_CONF.items():
            builder = builder.config(key, value)
        warehouse = warehouse_dir or os.path.join(tempfile.gettempdir(), "dataplatform-warehouse")
        builder = builder.config("spark.sql.warehouse.dir", warehouse)

    for key, value in (extra_conf or {}).items():
        builder = builder.config(key, value)

    if local and not is_databricks_runtime():
        from delta import configure_spark_with_delta_pip

        builder = configure_spark_with_delta_pip(builder)

    spark = builder.getOrCreate()
    spark.sparkContext.setLogLevel("ERROR" if local else "WARN")
    logger.info("SparkSession ready (version=%s, local=%s)", spark.version, local)
    return spark


def schema_from_ddl(spark: SparkSession, ddl: str) -> StructType:
    """Parse a DDL string such as ``"id STRING, amount DECIMAL(18,2)"`` into a StructType."""
    return spark.createDataFrame([], schema=ddl).schema
