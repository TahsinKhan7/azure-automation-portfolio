from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

import pytest
from pyspark.sql import functions as F

from dataplatform.etl import transforms as T

pytestmark = pytest.mark.spark


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        (" Claim Amount (GBP) ", "claim_amount_gbp"),
        ("Policy-Number", "policy_number"),
        ("claim_id", "claim_id"),
        ("2024 Total", "_2024_total"),
        ("ALL__CAPS", "all_caps"),
        ("", "_unnamed"),
        ("_ingested_at", "_ingested_at"),
        ("__meta__", "_meta"),
    ],
)
def test_normalise_column_name(raw: str, expected: str) -> None:
    assert T.normalise_column_name(raw) == expected


def test_clean_column_names(raw_claims_df) -> None:
    cleaned = T.clean_column_names(raw_claims_df)
    assert cleaned.columns == [
        "claim_id",
        "policy_number",
        "claim_date",
        "claim_type",
        "claim_amount_gbp",
        "business_unit",
        "status",
        "_ingested_at",
    ]
    assert cleaned.count() == raw_claims_df.count()


def test_clean_column_names_rejects_collisions(spark) -> None:
    df = spark.createDataFrame([(1, 2)], ["Claim Id", "claim_id"])
    with pytest.raises(ValueError, match="normalise to 'claim_id'"):
        T.clean_column_names(df)


def test_rename_columns_ignores_missing(claims_df) -> None:
    renamed = T.rename_columns(claims_df, {"claim_id": "id", "not_there": "x"})
    assert "id" in renamed.columns and "claim_id" not in renamed.columns


def test_trim_strings(spark) -> None:
    df = spark.createDataFrame([("  a ", 1)], ["s", "n"])
    row = T.trim_strings(df).first()
    assert row["s"] == "a" and row["n"] == 1


def test_standardise_nulls_converts_sentinels(spark) -> None:
    df = spark.createDataFrame([("N/A",), (" null ",), ("",), ("real",), (None,)], ["v"])
    values = [r["v"] for r in T.standardise_nulls(df).collect()]
    assert values == [None, None, None, "real", None]


def test_standardise_nulls_with_default_and_subset(spark) -> None:
    df = spark.createDataFrame([("NA", "NA")], ["a", "b"])
    row = T.standardise_nulls(df, columns=["a"], default="UNKNOWN").first()
    assert row["a"] == "UNKNOWN"
    assert row["b"] == "NA"


def test_deduplicate_latest_keeps_newest(claims_df) -> None:
    deduped = T.deduplicate_latest(claims_df, ["claim_id"], "_ingested_at")
    assert deduped.count() == 6
    c001 = deduped.filter(F.col("claim_id") == "C001").first()
    assert c001["claim_amount"] == Decimal("1250.00")
    assert c001["status"] == "settled"


def test_deduplicate_latest_ascending_keeps_oldest(claims_df) -> None:
    deduped = T.deduplicate_latest(claims_df, ["claim_id"], "_ingested_at", descending=False)
    assert deduped.filter(F.col("claim_id") == "C001").first()["status"] == "open"


def test_deduplicate_without_order_column_falls_back(claims_df) -> None:
    assert T.deduplicate_latest(claims_df, ["claim_id"], order_column=None).count() == 6
    assert T.deduplicate_latest(claims_df, ["claim_id"], order_column="missing").count() == 6


def test_deduplicate_requires_keys(claims_df) -> None:
    with pytest.raises(ValueError):
        T.deduplicate_latest(claims_df, [])


def test_cast_schema_casts_and_adds_missing(spark) -> None:
    df = spark.createDataFrame([("12.50", "2025-01-01")], ["amount", "d"])
    out = T.cast_schema(df, {"amount": "decimal(10,2)", "d": "date", "extra": "int"})
    row = out.first()
    assert row["amount"] == Decimal("12.50")
    assert row["d"] == date(2025, 1, 1)
    assert row["extra"] is None
    assert dict(out.dtypes)["extra"] == "int"


def test_cast_schema_strict_and_drop_unlisted(spark) -> None:
    df = spark.createDataFrame([("1", "x")], ["a", "b"])
    with pytest.raises(ValueError, match="missing"):
        T.cast_schema(df, {"zzz": "int"}, strict=True)
    assert T.cast_schema(df, {"a": "int"}, drop_unlisted=True).columns == ["a"]


def test_add_audit_columns(claims_df) -> None:
    out = T.add_audit_columns(claims_df, etl_version="9.9", run_id="run-1")
    row = out.first()
    assert isinstance(row["_processed_at"], datetime)
    assert row["_etl_version"] == "9.9" and row["_run_id"] == "run-1"


def test_derive_period_columns(claims_df) -> None:
    out = T.derive_period_columns(claims_df, "claim_date", include_quarter=True)
    row = out.filter(F.col("claim_id") == "C004").first()
    assert (row["year"], row["month"], row["year_month"], row["quarter"]) == (2025, 2, "2025-02", 1)


def test_derive_period_columns_prefix(claims_df) -> None:
    out = T.derive_period_columns(claims_df, "claim_date", prefix="claim_")
    assert {"claim_year", "claim_month", "claim_year_month"} <= set(out.columns)


def test_select_columns(claims_df) -> None:
    assert T.select_columns(claims_df, ["claim_id", "status"]).columns == ["claim_id", "status"]
    with pytest.raises(ValueError):
        T.select_columns(claims_df, ["nope"])
    assert T.select_columns(claims_df, ["nope", "claim_id"], allow_missing=True).columns == [
        "claim_id"
    ]
