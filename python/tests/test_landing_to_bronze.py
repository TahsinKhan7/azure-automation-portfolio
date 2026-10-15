from __future__ import annotations

import json
from pathlib import Path

import pytest
from pyspark.sql import functions as F
from pyspark.sql.types import StringType, StructField, StructType

from dataplatform.etl.landing_to_bronze import (
    CORRUPT_RECORD_COLUMN,
    IngestConfig,
    ingest_config_from_ddl,
    run_landing_to_bronze,
    split_bad_records,
    with_corrupt_record_column,
)

pytestmark = pytest.mark.spark

CLAIMS_DDL = "claim_id STRING, policy_number STRING, claim_date DATE, claim_amount DECIMAL(18,2)"


def test_ingest_config_validation() -> None:
    schema = StructType([StructField("a", StringType())])
    with pytest.raises(ValueError, match="Unsupported source_format"):
        IngestConfig("x", "avro", schema)
    with pytest.raises(ValueError, match="checkpoint_path"):
        IngestConfig("x", "csv", schema, use_autoloader=True)


def test_with_corrupt_record_column_is_idempotent() -> None:
    schema = StructType([StructField("a", StringType())])
    once = with_corrupt_record_column(schema)
    assert once.fieldNames() == ["a", CORRUPT_RECORD_COLUMN]
    assert with_corrupt_record_column(once) == once


def _write_csv(folder: Path) -> None:
    folder.mkdir(parents=True)
    (folder / "claims_2025-01.csv").write_text(
        "claim_id,policy_number,claim_date,claim_amount\n"
        "C001,POL-000001,2025-01-10,1200.00\n"
        "C002,POL-000002,2025-01-15,5400.50\n"
        "C003,POL-000003,not-a-date,100.00\n"  # malformed date -> quarantine
        "C004,POL-000004,2025-01-20,abc\n"  # malformed amount -> quarantine
    )


def test_csv_ingest_quarantines_bad_rows(spark, tmp_path: Path) -> None:
    _write_csv(tmp_path / "landing")
    config = ingest_config_from_ddl(spark, "claims", "csv", CLAIMS_DDL, options={"header": "true"})
    result = run_landing_to_bronze(
        spark,
        str(tmp_path / "landing"),
        str(tmp_path / "bronze"),
        str(tmp_path / "quarantine"),
        config,
        fmt="delta",
        run_id="run-1",
    )
    assert (result.rows_ingested, result.rows_quarantined, result.rows_read) == (2, 2, 4)

    bronze = spark.read.format("delta").load(str(tmp_path / "bronze"))
    assert bronze.count() == 2
    assert {"_ingested_at", "_source_file", "_ingest_run_id", "_dataset"} <= set(bronze.columns)
    assert CORRUPT_RECORD_COLUMN not in bronze.columns
    assert bronze.first()["_ingest_run_id"] == "run-1"
    assert bronze.first()["_source_file"].endswith("claims_2025-01.csv")

    quarantine = spark.read.format("delta").load(str(tmp_path / "quarantine"))
    raw_lines = {r[CORRUPT_RECORD_COLUMN] for r in quarantine.collect()}
    assert raw_lines == {"C003,POL-000003,not-a-date,100.00", "C004,POL-000004,2025-01-20,abc"}


def test_csv_ingest_appends_on_rerun(spark, tmp_path: Path) -> None:
    _write_csv(tmp_path / "landing")
    config = ingest_config_from_ddl(spark, "claims", "csv", CLAIMS_DDL, options={"header": "true"})
    args = (
        spark,
        str(tmp_path / "landing"),
        str(tmp_path / "bronze"),
        str(tmp_path / "quarantine"),
        config,
    )
    run_landing_to_bronze(*args)
    run_landing_to_bronze(*args)
    assert spark.read.format("delta").load(str(tmp_path / "bronze")).count() == 4


def test_json_ingest(spark, tmp_path: Path) -> None:
    landing = tmp_path / "landing"
    landing.mkdir()
    good = [
        {"policy_number": "POL-000001", "annual_premium": 320.5},
        {"policy_number": "POL-000002", "annual_premium": 99.0},
    ]
    lines = [json.dumps(g) for g in good] + [
        '{"policy_number": "POL-000003", "annual_premium": '
    ]  # truncated JSON
    (landing / "policies.json").write_text("\n".join(lines) + "\n")

    config = ingest_config_from_ddl(
        spark, "policies", "json", "policy_number STRING, annual_premium DOUBLE"
    )
    result = run_landing_to_bronze(
        spark, str(landing), str(tmp_path / "bronze"), str(tmp_path / "q"), config, fmt="parquet"
    )
    assert (result.rows_ingested, result.rows_quarantined) == (2, 1)
    assert spark.read.parquet(str(tmp_path / "q")).count() == 1


def test_parquet_ingest_has_no_quarantine(spark, customers_df, tmp_path: Path) -> None:
    landing = str(tmp_path / "landing")
    customers_df.write.parquet(landing)
    from conftest import CUSTOMERS_SCHEMA

    config = ingest_config_from_ddl(spark, "customers", "parquet", CUSTOMERS_SCHEMA)
    result = run_landing_to_bronze(
        spark, landing, str(tmp_path / "bronze"), str(tmp_path / "q"), config
    )
    assert (result.rows_ingested, result.rows_quarantined) == (3, 0)
    assert not (tmp_path / "q").exists()


def test_split_bad_records_without_corrupt_column(customers_df) -> None:
    good, bad = split_bad_records(customers_df)
    assert good.count() == 3 and bad.count() == 0
    assert CORRUPT_RECORD_COLUMN in bad.columns


def test_partitioned_bronze_write(spark, tmp_path: Path) -> None:
    _write_csv(tmp_path / "landing")
    config = ingest_config_from_ddl(
        spark,
        "claims",
        "csv",
        CLAIMS_DDL,
        options={"header": "true"},
        partition_columns=["policy_number"],
    )
    run_landing_to_bronze(
        spark, str(tmp_path / "landing"), str(tmp_path / "bronze"), str(tmp_path / "q"), config
    )
    bronze = spark.read.format("delta").load(str(tmp_path / "bronze"))
    assert bronze.filter(F.col("policy_number") == "POL-000001").count() == 1
    assert (tmp_path / "bronze" / "policy_number=POL-000001").is_dir()
