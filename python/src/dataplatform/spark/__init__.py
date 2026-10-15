"""SparkSession helpers."""

from dataplatform.spark.session import get_spark, is_databricks_runtime, schema_from_ddl

__all__ = ["get_spark", "is_databricks_runtime", "schema_from_ddl"]
