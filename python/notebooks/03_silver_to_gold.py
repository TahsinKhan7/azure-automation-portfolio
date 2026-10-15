# Databricks notebook source
# MAGIC %md
# MAGIC # 03 - Silver to Gold
# MAGIC Build consumption-ready tables: `daily_summary`, `monthly_trends` (with month-on-month
# MAGIC change and a rolling average) and a single-row `kpi_snapshot`.
# MAGIC
# MAGIC Runs only after the data quality gate (task dependency in the job definition).

# COMMAND ----------

dbutils.widgets.dropdown("env", "dev", ["dev", "ite", "iqe", "preprod", "prod"])
dbutils.widgets.text("dataset", "claims")
dbutils.widgets.text("rolling_window", "3")
dbutils.widgets.text("run_id", "")

# COMMAND ----------

import logging
import uuid

from dataplatform.config import load_settings
from dataplatform.etl.silver_to_gold import GoldConfig, run_silver_to_gold

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

env = dbutils.widgets.get("env")
dataset_name = dbutils.widgets.get("dataset")
rolling_window = int(dbutils.widgets.get("rolling_window"))
run_id = dbutils.widgets.get("run_id") or uuid.uuid4().hex

settings = load_settings(env, config_dir="/Workspace/Shared/dataplatform/config")
dataset = settings.dataset(dataset_name)
if not dataset.date_column or not dataset.value_column:
    raise ValueError(f"Dataset '{dataset.name}' does not define date/value columns for gold")

# COMMAND ----------

config = GoldConfig(
    date_column=dataset.date_column,
    value_column=dataset.value_column,
    group_columns=dataset.group_columns,
    rolling_window=rolling_window,
)
counts = run_silver_to_gold(
    spark,
    silver_path=settings.path("silver", dataset.name),
    gold_base_path=settings.path("gold", dataset.name),
    config=config,
    run_id=run_id,
)

# COMMAND ----------

for table_name in counts:
    spark.sql(
        f"CREATE TABLE IF NOT EXISTS {settings.table('gold', f'{dataset.name}_{table_name}')} "
        f"USING DELTA LOCATION '{settings.path('gold', dataset.name, table_name)}'"
    )

display(spark.table(settings.table("gold", f"{dataset.name}_monthly_trends")).orderBy("year_month"))

# COMMAND ----------

dbutils.notebook.exit(str(counts))
