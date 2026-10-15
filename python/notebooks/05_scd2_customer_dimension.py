# Databricks notebook source
# MAGIC %md
# MAGIC # 05 - SCD Type 2 Customer Dimension
# MAGIC Maintain `dim_customer` with full history: new customers are inserted, changed
# MAGIC attributes expire the current row and open a new one, unchanged rows are untouched.
# MAGIC Change detection is hash based (`_hash_diff`) and the apply is one atomic Delta `MERGE`.

# COMMAND ----------

dbutils.widgets.dropdown("env", "dev", ["dev", "ite", "iqe", "preprod", "prod"])
dbutils.widgets.text("dataset", "customers")
dbutils.widgets.text("effective_from", "")

# COMMAND ----------

import logging

from dataplatform.config import load_settings
from dataplatform.etl.scd2_merge import Scd2Config, apply_scd2
from dataplatform.etl.transforms import deduplicate_latest

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

env = dbutils.widgets.get("env")
dataset_name = dbutils.widgets.get("dataset")
effective_from = dbutils.widgets.get("effective_from") or None

settings = load_settings(env, config_dir="/Workspace/Shared/dataplatform/config")
dataset = settings.dataset(dataset_name)
if dataset.scd2 is None:
    raise ValueError(f"Dataset '{dataset.name}' has no scd2 settings")

# COMMAND ----------

config = Scd2Config(
    key_columns=dataset.key_columns,
    tracked_columns=dataset.scd2.tracked_columns,
    source_effective_from_column=dataset.scd2.effective_from_column,
)

# The MERGE requires one row per key in the source; keep the latest version if the silver
# table carries several updates for the same customer.
source = spark.read.format("delta").load(settings.path("silver", dataset.name))
source = deduplicate_latest(source, dataset.key_columns, dataset.order_column)

dimension_path = settings.path("gold", f"dim_{dataset.name}")
result = apply_scd2(spark, dimension_path, source, config, effective_from=effective_from)

# COMMAND ----------

spark.sql(
    f"CREATE TABLE IF NOT EXISTS {settings.table('gold', f'dim_{dataset.name}')} "
    f"USING DELTA LOCATION '{dimension_path}'"
)
display(spark.read.format("delta").load(dimension_path).groupBy("is_current").count())

# COMMAND ----------

dbutils.notebook.exit(
    f"dim_{dataset.name}: inserted={result.inserted} expired={result.expired} "
    f"unchanged={result.unchanged} initial_load={result.initial_load}"
)
