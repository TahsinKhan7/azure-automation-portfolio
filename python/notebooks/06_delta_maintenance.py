# Databricks notebook source
# MAGIC %md
# MAGIC # 06 - Delta Maintenance
# MAGIC Weekly `OPTIMIZE` (with Z-ORDER on the usual filter columns) and `VACUUM` for the
# MAGIC silver and gold tables. Only tables on the allow-list below are touched, and the
# MAGIC `dry_run` widget prints the statements without executing them.

# COMMAND ----------

dbutils.widgets.dropdown("env", "dev", ["dev", "ite", "iqe", "preprod", "prod"])
dbutils.widgets.dropdown("dry_run", "true", ["true", "false"])
dbutils.widgets.text("retention_hours", "")

# COMMAND ----------

import logging

from dataplatform.config import load_settings
from dataplatform.databricks.delta_maintenance import DeltaMaintenanceRunner, MaintenanceTask

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

env = dbutils.widgets.get("env")
dry_run = dbutils.widgets.get("dry_run").lower() == "true"
settings = load_settings(env, config_dir="/Workspace/Shared/dataplatform/config")
retention = int(dbutils.widgets.get("retention_hours") or settings.job.delta_retention_hours)

# COMMAND ----------

tasks = [
    MaintenanceTask(
        settings.table("silver", "claims"),
        zorder_by=("claim_date", "policy_number"),
        vacuum_retention_hours=retention,
    ),
    MaintenanceTask(
        settings.table("silver", "policies"),
        zorder_by=("policy_number",),
        vacuum_retention_hours=retention,
    ),
    MaintenanceTask(
        settings.table("gold", "dim_customers"),
        zorder_by=("customer_id",),
        vacuum_retention_hours=retention,
    ),
    MaintenanceTask(
        settings.table("gold", "claims_monthly_trends"),
        vacuum_retention_hours=retention,
    ),
]
allow_list = [task.table for task in tasks]

# COMMAND ----------

runner = DeltaMaintenanceRunner(spark, allow_list=allow_list, dry_run=dry_run)
before = {} if dry_run else {t.table: runner.table_detail(t.table) for t in tasks}
outcomes = runner.run(tasks)

# COMMAND ----------

rows = []
for outcome in outcomes:
    detail = {} if dry_run else runner.table_detail(outcome.table)
    rows.append(
        {
            "table": outcome.table,
            "executed": outcome.executed,
            "error": outcome.error,
            "files_before": before.get(outcome.table, {}).get("numFiles"),
            "files_after": detail.get("numFiles"),
            "size_bytes_after": detail.get("sizeInBytes"),
            "statements": " ; ".join(outcome.statements),
        }
    )
display(spark.createDataFrame(rows))

# COMMAND ----------

failed = [o.table for o in outcomes if o.error]
if failed:
    raise RuntimeError(f"Maintenance skipped tables with errors: {failed}")
dbutils.notebook.exit(f"maintenance complete (dry_run={dry_run}) for {len(outcomes)} table(s)")
