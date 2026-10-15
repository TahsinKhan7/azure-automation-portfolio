# Databricks notebook source
# MAGIC %md
# MAGIC # 02 - Bronze to Silver
# MAGIC Conform a bronze dataset: snake_case columns, declared types, sentinel nulls removed,
# MAGIC latest record per business key, partition columns derived from the business date.
# MAGIC
# MAGIC The transformation is `dataplatform.etl.bronze_to_silver.transform_bronze_to_silver`,
# MAGIC a pure function covered by unit tests; this notebook only wires paths and parameters.

# COMMAND ----------

dbutils.widgets.dropdown("env", "dev", ["dev", "ite", "iqe", "preprod", "prod"])
dbutils.widgets.text("dataset", "claims")
dbutils.widgets.text("run_id", "")

# COMMAND ----------

import logging
import uuid

from dataplatform.config import load_settings
from dataplatform.etl.bronze_to_silver import SilverConfig, run_bronze_to_silver

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

env = dbutils.widgets.get("env")
dataset_name = dbutils.widgets.get("dataset")
run_id = dbutils.widgets.get("run_id") or uuid.uuid4().hex

settings = load_settings(env, config_dir="/Workspace/Shared/dataplatform/config")
dataset = settings.dataset(dataset_name)
spark.conf.set("spark.sql.shuffle.partitions", settings.job.shuffle_partitions)

# COMMAND ----------

config = SilverConfig(
    key_columns=dataset.key_columns,
    order_column=dataset.order_column,
    date_column=dataset.date_column,
    partition_columns=dataset.partition_columns,
    cast_schema=dataset.cast_schema,
    null_default="UNKNOWN",
)

result = run_bronze_to_silver(
    spark,
    source_path=settings.path("bronze", dataset.name),
    target_path=settings.path("silver", dataset.name),
    config=config,
    run_id=run_id,
)

# COMMAND ----------

spark.sql(
    f"CREATE TABLE IF NOT EXISTS {settings.table('silver', dataset.name)} "
    f"USING DELTA LOCATION '{settings.path('silver', dataset.name)}'"
)
display(spark.table(settings.table("silver", dataset.name)).limit(20))

# COMMAND ----------

dbutils.jobs.taskValues.set("rows_out", result.rows_out)
dbutils.notebook.exit(f"{dataset.name}: {result.rows_in} in, {result.rows_out} out")
