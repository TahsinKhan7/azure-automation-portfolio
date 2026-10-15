# Databricks notebook source
# MAGIC %md
# MAGIC # 01 - Landing to Bronze
# MAGIC Ingest raw files for one dataset with an explicit schema, quarantine malformed records
# MAGIC and append to the bronze Delta table with ingestion metadata.
# MAGIC
# MAGIC Parameters come from job `base_parameters` (or the widgets when run interactively).
# MAGIC Set `use_autoloader=true` to discover files incrementally with Auto Loader.

# COMMAND ----------

dbutils.widgets.dropdown("env", "dev", ["dev", "ite", "iqe", "preprod", "prod"])
dbutils.widgets.text("dataset", "claims")
dbutils.widgets.dropdown("use_autoloader", "false", ["true", "false"])
dbutils.widgets.text("run_id", "")

# COMMAND ----------

import logging
import uuid

from dataplatform.config import load_settings
from dataplatform.etl.landing_to_bronze import ingest_config_from_ddl, run_landing_to_bronze

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

env = dbutils.widgets.get("env")
dataset_name = dbutils.widgets.get("dataset")
use_autoloader = dbutils.widgets.get("use_autoloader").lower() == "true"
run_id = dbutils.widgets.get("run_id") or uuid.uuid4().hex

settings = load_settings(env, config_dir="/Workspace/Shared/dataplatform/config")
dataset = settings.dataset(dataset_name)

# COMMAND ----------

config = ingest_config_from_ddl(
    spark,
    dataset.name,
    dataset.source_format,
    dataset.schema_ddl,
    options=dataset.source_options,
    use_autoloader=use_autoloader,
    checkpoint_path=settings.path("checkpoints", dataset.name, "landing_to_bronze")
    if use_autoloader
    else None,
)

result = run_landing_to_bronze(
    spark,
    source_path=settings.path("landing", dataset.name),
    target_path=settings.path("bronze", dataset.name),
    quarantine_path=settings.path("quarantine", dataset.name),
    config=config,
    run_id=run_id,
)

# COMMAND ----------

# Register the bronze location in Unity Catalog so analysts can query it by name.
spark.sql(
    f"CREATE TABLE IF NOT EXISTS {settings.table('bronze', dataset.name)} "
    f"USING DELTA LOCATION '{settings.path('bronze', dataset.name)}'"
)

# COMMAND ----------

dbutils.jobs.taskValues.set("rows_ingested", result.rows_ingested)
dbutils.jobs.taskValues.set("rows_quarantined", result.rows_quarantined)
dbutils.notebook.exit(
    f"{dataset.name}: {result.rows_ingested} ingested, {result.rows_quarantined} quarantined"
)
