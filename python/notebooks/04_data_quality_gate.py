# Databricks notebook source
# MAGIC %md
# MAGIC # 04 - Data Quality Gate
# MAGIC Run the dataset's YAML expectation suite against a lakehouse layer. Blocking failures
# MAGIC raise `DataQualityError`, which fails the task and stops downstream tasks (gold) from
# MAGIC running. Results are also written to a Delta audit table for trend reporting.

# COMMAND ----------

dbutils.widgets.dropdown("env", "dev", ["dev", "ite", "iqe", "preprod", "prod"])
dbutils.widgets.text("dataset", "claims")
dbutils.widgets.dropdown("layer", "silver", ["bronze", "silver", "gold"])
dbutils.widgets.dropdown("fail_on_error", "true", ["true", "false"])

# COMMAND ----------

import logging

from pyspark.sql import functions as F

from dataplatform.config import load_settings
from dataplatform.quality.expectations import load_suite, run_suite
from dataplatform.quality.validator import DataQualityError

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

env = dbutils.widgets.get("env")
dataset_name = dbutils.widgets.get("dataset")
layer = dbutils.widgets.get("layer")
fail_on_error = dbutils.widgets.get("fail_on_error").lower() == "true"

settings = load_settings(env, config_dir="/Workspace/Shared/dataplatform/config")
dataset = settings.dataset(dataset_name)
if not dataset.quality_suite:
    raise ValueError(f"Dataset '{dataset.name}' has no quality suite configured")

# COMMAND ----------

suite = load_suite(settings.resolve(dataset.quality_suite))
df = spark.read.format("delta").load(settings.path(layer, dataset.name))

# Reference frames for referential-integrity expectations, keyed by name used in the YAML.
reference_frames = {}
if "policies" in settings.datasets and dataset.name != "policies":
    policies_path = settings.path("silver", "policies")
    reference_frames["policies"] = spark.read.format("delta").load(policies_path)

# COMMAND ----------

error: DataQualityError | None = None
try:
    summary = run_suite(df, suite, reference_frames=reference_frames, fail_on_error=fail_on_error)
except DataQualityError as exc:
    summary, error = exc.summary, exc

logging.getLogger("dataplatform.dq_gate").info("\n%s", summary)

# COMMAND ----------

# Persist results for trend dashboards (one row per check per run).
audit_rows = [
    {
        "environment": env,
        "dataset": summary.dataset,
        "layer": layer,
        "validated_at": summary.validated_at,
        **r.to_dict(),
    }
    for r in summary.results
]
audit_table = settings.table("gold", "dq_check_results")
(
    spark.createDataFrame(audit_rows)
    .withColumn("validated_at", F.to_timestamp("validated_at"))
    .write.format("delta")
    .mode("append")
    .option("mergeSchema", "true")
    .saveAsTable(audit_table)
)

# COMMAND ----------

dbutils.jobs.taskValues.set("dq_passed", summary.ok)
dbutils.jobs.taskValues.set("dq_failed_checks", summary.failed)
if error is not None:
    raise error
dbutils.notebook.exit(f"{summary.dataset}: {summary.passed}/{summary.total} passed")
