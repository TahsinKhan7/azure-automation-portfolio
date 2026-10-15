from __future__ import annotations

from decimal import Decimal

import pytest
from pyspark.sql import functions as F

from dataplatform.etl.bronze_to_silver import (
    LayerResult,
    SilverConfig,
    run_bronze_to_silver,
    transform_bronze_to_silver,
)

pytestmark = pytest.mark.spark

CONFIG = SilverConfig(
    key_columns=["claim_id"],
    order_column="_ingested_at",
    date_column="claim_date",
    partition_columns=["year", "month"],
    cast_schema={
        "claim_amount_gbp": "decimal(18,2)",
        "claim_date": "date",
        "_ingested_at": "timestamp",
    },
    null_default="UNKNOWN",
)


def test_silver_config_requires_keys() -> None:
    with pytest.raises(ValueError):
        SilverConfig(key_columns=[])


def test_transform_conforms_names_types_and_duplicates(raw_claims_df) -> None:
    silver = transform_bronze_to_silver(raw_claims_df, CONFIG, run_id="r1")
    assert silver.count() == 3
    types = dict(silver.dtypes)
    assert types["claim_amount_gbp"] == "decimal(18,2)" and types["claim_date"] == "date"
    assert {"year", "month", "year_month", "_processed_at", "_etl_version", "_run_id"} <= set(
        silver.columns
    )
    latest = silver.filter(F.col("claim_id") == "C001").first()
    assert latest["claim_amount_gbp"] == Decimal("1250.00")


def test_transform_standardises_nulls(raw_claims_df) -> None:
    silver = transform_bronze_to_silver(raw_claims_df, CONFIG)
    c002 = silver.filter(F.col("claim_id") == "C002").first()
    c003 = silver.filter(F.col("claim_id") == "C003").first()
    assert c002["claim_type"] == "UNKNOWN"  # "N/A" sentinel
    assert c002["business_unit"] == "retail"  # trimmed
    assert c003["business_unit"] == "UNKNOWN"  # empty string


def test_run_bronze_to_silver_writes_partitioned_delta(spark, raw_claims_df, tmp_path) -> None:
    bronze = str(tmp_path / "bronze")
    silver = str(tmp_path / "silver")
    raw_claims_df.write.format("parquet").save(bronze)

    result = run_bronze_to_silver(
        spark, bronze, silver, CONFIG, fmt="delta", source_format="parquet"
    )

    assert isinstance(result, LayerResult)
    assert (result.rows_in, result.rows_out, result.rows_dropped) == (4, 3, 1)
    written = spark.read.format("delta").load(silver)
    assert written.count() == 3
    assert any(p.name.startswith("year=") for p in (tmp_path / "silver").iterdir())


def test_run_bronze_to_silver_is_idempotent(spark, raw_claims_df, tmp_path) -> None:
    bronze = str(tmp_path / "bronze")
    silver = str(tmp_path / "silver")
    raw_claims_df.write.format("parquet").save(bronze)
    run_bronze_to_silver(spark, bronze, silver, CONFIG, source_format="parquet")
    run_bronze_to_silver(spark, bronze, silver, CONFIG, source_format="parquet")
    assert spark.read.format("delta").load(silver).count() == 3
