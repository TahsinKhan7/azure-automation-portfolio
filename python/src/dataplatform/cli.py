"""Command-line entry points.

Examples::

    dataplatform etl run --layer bronze-to-silver --env dev --dataset claims
    dataplatform dq run --env dev --dataset claims
    dataplatform jobs deploy --env dev --file config/jobs/medallion_pipeline.yml --dry-run
    dataplatform maintenance run --env dev --table dataplatform_dev.silver.claims --dry-run

Each sub-command resolves settings for ``--env``, builds the required objects and delegates
to the library functions; the CLI itself holds no business logic.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from collections.abc import Sequence
from typing import Any

from dataplatform import __version__
from dataplatform.config.settings import ENVIRONMENTS, Settings, load_settings

logger = logging.getLogger("dataplatform.cli")

LAYERS = ("landing-to-bronze", "bronze-to-silver", "silver-to-gold")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="dataplatform", description="Medallion lakehouse toolkit")
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    parser.add_argument("-v", "--verbose", action="store_true", help="debug logging")
    sub = parser.add_subparsers(dest="command", required=True)

    def add_common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--env", required=True, choices=ENVIRONMENTS, help="target environment")
        p.add_argument("--config-dir", help="directory with <env>.yml and datasets.yml")

    etl = sub.add_parser("etl", help="run a medallion layer").add_subparsers(
        dest="action", required=True
    )
    etl_run = etl.add_parser("run", help="run one layer for one dataset")
    add_common(etl_run)
    etl_run.add_argument("--layer", required=True, choices=LAYERS)
    etl_run.add_argument("--dataset", required=True)
    etl_run.add_argument(
        "--format", default="delta", choices=("delta", "parquet"), help="storage format"
    )
    etl_run.add_argument("--local", action="store_true", help="use a local SparkSession")
    etl_run.add_argument("--source", help="override source path")
    etl_run.add_argument("--target", help="override target path")
    etl_run.set_defaults(handler=cmd_etl_run)

    dq = sub.add_parser("dq", help="data quality").add_subparsers(dest="action", required=True)
    dq_run = dq.add_parser("run", help="run an expectation suite against a table")
    add_common(dq_run)
    dq_run.add_argument("--dataset", required=True)
    dq_run.add_argument("--layer", default="silver", help="lakehouse layer to validate")
    dq_run.add_argument("--suite", help="path to a suite YAML (defaults to the dataset's suite)")
    dq_run.add_argument("--format", default="delta", choices=("delta", "parquet"))
    dq_run.add_argument("--local", action="store_true")
    dq_run.add_argument("--source", help="override source path")
    dq_run.add_argument("--no-fail", action="store_true", help="report but exit 0 on failures")
    dq_run.set_defaults(handler=cmd_dq_run)

    jobs = sub.add_parser("jobs", help="Databricks jobs").add_subparsers(
        dest="action", required=True
    )
    jobs_deploy = jobs.add_parser("deploy", help="create-or-update jobs from YAML")
    add_common(jobs_deploy)
    jobs_deploy.add_argument("--file", required=True, help="job definitions YAML")
    jobs_deploy.add_argument("--dry-run", action="store_true")
    jobs_deploy.set_defaults(handler=cmd_jobs_deploy)

    maint = sub.add_parser("maintenance", help="Delta maintenance").add_subparsers(
        dest="action", required=True
    )
    maint_run = maint.add_parser("run", help="OPTIMIZE / VACUUM allow-listed tables")
    add_common(maint_run)
    maint_run.add_argument("--table", action="append", required=True, help="table (repeatable)")
    maint_run.add_argument("--zorder-by", help="comma-separated columns")
    maint_run.add_argument("--retention-hours", type=int, default=None)
    maint_run.add_argument("--dry-run", action="store_true")
    maint_run.add_argument("--local", action="store_true")
    maint_run.set_defaults(handler=cmd_maintenance_run)

    return parser


# --------------------------------------------------------------------------- handlers
def cmd_etl_run(args: argparse.Namespace) -> int:
    from dataplatform.spark.session import get_spark

    settings = load_settings(args.env, args.config_dir)
    dataset = settings.dataset(args.dataset)
    spark = get_spark(f"dataplatform-{args.layer}-{args.dataset}", local=args.local)

    if args.layer == "landing-to-bronze":
        from dataplatform.etl.landing_to_bronze import ingest_config_from_ddl, run_landing_to_bronze

        config = ingest_config_from_ddl(
            spark,
            dataset.name,
            dataset.source_format,
            dataset.schema_ddl,
            options=dataset.source_options,
        )
        result = run_landing_to_bronze(
            spark,
            args.source or settings.path("landing", dataset.name),
            args.target or settings.path("bronze", dataset.name),
            settings.path("quarantine", dataset.name),
            config,
            fmt=args.format,
        )
        _emit({"rows_ingested": result.rows_ingested, "rows_quarantined": result.rows_quarantined})
    elif args.layer == "bronze-to-silver":
        from dataplatform.etl.bronze_to_silver import SilverConfig, run_bronze_to_silver

        config = SilverConfig(
            key_columns=dataset.key_columns,
            order_column=dataset.order_column,
            date_column=dataset.date_column,
            partition_columns=dataset.partition_columns,
            cast_schema=dataset.cast_schema,
        )
        result = run_bronze_to_silver(
            spark,
            args.source or settings.path("bronze", dataset.name),
            args.target or settings.path("silver", dataset.name),
            config,
            fmt=args.format,
        )
        _emit({"rows_in": result.rows_in, "rows_out": result.rows_out})
    else:
        from dataplatform.etl.silver_to_gold import GoldConfig, run_silver_to_gold

        if not dataset.date_column or not dataset.value_column:
            parser_error(f"Dataset '{dataset.name}' has no date/value columns for gold aggregation")
        config = GoldConfig(dataset.date_column, dataset.value_column, dataset.group_columns)
        counts = run_silver_to_gold(
            spark,
            args.source or settings.path("silver", dataset.name),
            args.target or settings.path("gold", dataset.name),
            config,
            fmt=args.format,
        )
        _emit(counts)
    return 0


def cmd_dq_run(args: argparse.Namespace) -> int:
    from dataplatform.quality.expectations import load_suite, run_suite
    from dataplatform.quality.validator import DataQualityError
    from dataplatform.spark.session import get_spark

    settings = load_settings(args.env, args.config_dir)
    dataset = settings.dataset(args.dataset)
    suite_path = args.suite or (
        settings.resolve(dataset.quality_suite) if dataset.quality_suite else None
    )
    if not suite_path:
        parser_error(f"Dataset '{dataset.name}' has no quality suite; pass --suite")
    suite = load_suite(suite_path)
    spark = get_spark(f"dataplatform-dq-{args.dataset}", local=args.local)
    df = spark.read.format(args.format).load(args.source or settings.path(args.layer, dataset.name))
    try:
        summary = run_suite(df, suite, fail_on_error=not args.no_fail)
    except DataQualityError as exc:
        _emit(exc.summary.to_dict())
        return 2
    _emit(summary.to_dict())
    return 0


def cmd_jobs_deploy(args: argparse.Namespace) -> int:
    from dataplatform.databricks.jobs_deployer import JobsDeployer

    settings = load_settings(args.env, args.config_dir)
    deployer = JobsDeployer(workspace_client(settings), dry_run=args.dry_run)
    results = deployer.deploy_file(args.file, settings.placeholders())
    _emit([{"job": r.job_name, "job_id": r.job_id, "action": r.action} for r in results])
    return 0


def cmd_maintenance_run(args: argparse.Namespace) -> int:
    from dataplatform.databricks.delta_maintenance import DeltaMaintenanceRunner, MaintenanceTask
    from dataplatform.spark.session import get_spark

    settings = load_settings(args.env, args.config_dir)
    spark = get_spark("dataplatform-maintenance", local=args.local)
    zorder = tuple(c.strip() for c in args.zorder_by.split(",")) if args.zorder_by else ()
    retention = (
        args.retention_hours
        if args.retention_hours is not None
        else settings.job.delta_retention_hours
    )
    tasks = [
        MaintenanceTask(t, zorder_by=zorder, vacuum_retention_hours=retention) for t in args.table
    ]
    runner = DeltaMaintenanceRunner(spark, allow_list=args.table, dry_run=args.dry_run)
    outcomes = runner.run(tasks)
    _emit(
        [
            {"table": o.table, "statements": o.statements, "executed": o.executed, "error": o.error}
            for o in outcomes
        ]
    )
    return 1 if any(o.error for o in outcomes) else 0


# ---------------------------------------------------------------------------- helpers
def workspace_client(settings: Settings) -> Any:
    """Build a Databricks SDK client; auth comes from the environment (PAT, Azure CLI, MSI)."""
    from databricks.sdk import WorkspaceClient

    return (
        WorkspaceClient(host=settings.workspace_host)
        if settings.workspace_host
        else WorkspaceClient()
    )


def parser_error(message: str) -> None:
    raise SystemExit(f"dataplatform: error: {message}")


def _emit(payload: Any) -> None:
    sys.stdout.write(json.dumps(payload, indent=2, default=str) + "\n")


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    return int(args.handler(args))


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
