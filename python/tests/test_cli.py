from __future__ import annotations

import json
from pathlib import Path

import pytest
from pyspark.sql import functions as F

from dataplatform import cli


def test_parser_etl_run_arguments() -> None:
    args = cli.build_parser().parse_args(
        ["etl", "run", "--layer", "bronze-to-silver", "--env", "dev", "--dataset", "claims"]
    )
    assert (args.command, args.action, args.layer, args.env, args.dataset) == (
        "etl",
        "run",
        "bronze-to-silver",
        "dev",
        "claims",
    )
    assert args.handler is cli.cmd_etl_run and args.format == "delta"


@pytest.mark.parametrize(
    "argv",
    [
        ["etl", "run", "--layer", "bronze-to-silver", "--dataset", "claims"],  # missing --env
        ["etl", "run", "--layer", "gold-to-platinum", "--env", "dev", "--dataset", "claims"],
        ["jobs", "deploy", "--env", "staging", "--file", "x.yml"],
        ["dq"],
    ],
)
def test_parser_rejects_invalid_invocations(argv: list[str]) -> None:
    with pytest.raises(SystemExit):
        cli.build_parser().parse_args(argv)


def test_version_flag(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as excinfo:
        cli.main(["--version"])
    assert excinfo.value.code == 0
    assert "dataplatform 1.0.0" in capsys.readouterr().out


def test_main_dispatches_to_handler(monkeypatch: pytest.MonkeyPatch) -> None:
    seen = {}

    def fake_handler(args):
        seen["layer"] = args.layer
        return 0

    monkeypatch.setattr(cli, "cmd_etl_run", fake_handler)
    # the parser binds handlers at build time, so rebuild via main()
    monkeypatch.setattr(cli, "build_parser", lambda: _parser_with(fake_handler))
    assert (
        cli.main(["etl", "run", "--layer", "silver-to-gold", "--env", "dev", "--dataset", "claims"])
        == 0
    )
    assert seen["layer"] == "silver-to-gold"


def _parser_with(handler):
    import argparse

    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command")
    etl = sub.add_parser("etl").add_subparsers(dest="action")
    run = etl.add_parser("run")
    run.add_argument("--layer")
    run.add_argument("--env")
    run.add_argument("--dataset")
    run.add_argument("-v", "--verbose", action="store_true")
    run.set_defaults(handler=handler)
    return parser


def test_jobs_deploy_dry_run(
    monkeypatch: pytest.MonkeyPatch, config_dir: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    from unittest.mock import MagicMock

    fake_workspace = MagicMock()
    fake_workspace.jobs.list.return_value = []
    monkeypatch.setattr(cli, "workspace_client", lambda settings: fake_workspace)
    code = cli.main(
        [
            "jobs",
            "deploy",
            "--env",
            "dev",
            "--config-dir",
            str(config_dir),
            "--file",
            str(config_dir / "jobs" / "medallion_pipeline.yml"),
            "--dry-run",
        ]
    )
    assert code == 0
    payload = json.loads(capsys.readouterr().out)
    assert [p["action"] for p in payload] == ["planned-create", "planned-create"]
    fake_workspace.jobs.create.assert_not_called()


@pytest.mark.spark
def test_dq_run_end_to_end_with_parquet(
    spark, claims_df, config_dir: Path, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    source = str(tmp_path / "silver")
    claims_df.dropDuplicates(["claim_id"]).withColumn(
        "_processed_at", F.current_timestamp()
    ).write.parquet(source)
    code = cli.main(
        [
            "dq",
            "run",
            "--env",
            "dev",
            "--dataset",
            "policies",
            "--suite",
            str(config_dir / "quality" / "claims_silver.yml"),
            "--source",
            source,
            "--format",
            "parquet",
            "--local",
            "--no-fail",
        ]
    )
    payload = json.loads(capsys.readouterr().out)
    assert code == 0
    assert payload["dataset"] == "claims_silver" and payload["total"] >= 8


@pytest.mark.spark
def test_dq_run_exit_code_on_failure(
    spark, claims_df, config_dir: Path, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    source = str(tmp_path / "silver")
    claims_df.withColumn("_processed_at", F.current_timestamp()).write.parquet(source)  # duplicates
    code = cli.main(
        [
            "dq",
            "run",
            "--env",
            "dev",
            "--dataset",
            "claims",
            "--source",
            source,
            "--format",
            "parquet",
            "--local",
        ]
    )
    assert code == 2
    assert json.loads(capsys.readouterr().out)["ok"] is False


@pytest.mark.spark
def test_etl_run_bronze_to_silver_locally(
    spark, raw_claims_df, config_dir: Path, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    bronze = str(tmp_path / "bronze")
    silver = str(tmp_path / "silver")
    raw_claims_df.selectExpr(
        "`Claim ID` as claim_id",
        "`Policy Number` as policy_number",
        "`Claim Date` as claim_date",
        "`Claim Type` as claim_type",
        "`Claim Amount (GBP)` as claim_amount",
        "`Business Unit` as business_unit",
        "Status as status",
        "cast(_ingested_at as timestamp) as _ingested_at",
    ).write.parquet(bronze)
    code = cli.main(
        [
            "etl",
            "run",
            "--layer",
            "bronze-to-silver",
            "--env",
            "dev",
            "--dataset",
            "claims",
            "--source",
            bronze,
            "--target",
            silver,
            "--format",
            "parquet",
            "--local",
        ]
    )
    assert code == 0
    assert json.loads(capsys.readouterr().out) == {"rows_in": 4, "rows_out": 3}
    assert {"year", "month"} <= set(spark.read.parquet(silver).columns)


@pytest.mark.spark
def test_maintenance_run_dry_run(config_dir: Path, capsys: pytest.CaptureFixture[str]) -> None:
    code = cli.main(
        [
            "maintenance",
            "run",
            "--env",
            "dev",
            "--table",
            "dataplatform_dev.silver.claims",
            "--zorder-by",
            "claim_date",
            "--dry-run",
            "--local",
        ]
    )
    payload = json.loads(capsys.readouterr().out)
    assert code == 0
    assert payload[0]["statements"] == [
        "OPTIMIZE dataplatform_dev.silver.claims ZORDER BY (claim_date)",
        "VACUUM dataplatform_dev.silver.claims RETAIN 168 HOURS",
    ]
