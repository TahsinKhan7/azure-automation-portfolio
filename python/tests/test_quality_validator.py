from __future__ import annotations

import json
from datetime import datetime, timezone

import pytest
from pyspark.sql import functions as F

from dataplatform.quality.quarantine import QuarantineRule, split_quarantine
from dataplatform.quality.validator import CheckResult, DataQualityError, DataQualityValidator

pytestmark = pytest.mark.spark


@pytest.fixture
def deduped(claims_df):
    return claims_df.dropDuplicates(["claim_id"])


def test_not_null_pass_and_fail(spark) -> None:
    df = spark.createDataFrame([("a", None), ("b", 1)], ["k", "v"])
    results = DataQualityValidator(df, "t").check_not_null(["k", "v"]).results
    assert [r.passed for r in results] == [True, False]
    assert results[1].failed == 1 and results[1].checked == 2


def test_unique_detects_duplicates(claims_df, deduped) -> None:
    assert not DataQualityValidator(claims_df, "t").check_unique(["claim_id"]).results[0].passed
    assert DataQualityValidator(deduped, "t").check_unique(["claim_id"]).results[0].passed


def test_accepted_values(deduped) -> None:
    v = DataQualityValidator(deduped, "t")
    v.check_accepted_values("claim_type", ["motor", "home", "travel"])
    v.check_accepted_values("claim_type", ["motor"])
    assert v.results[0].passed and not v.results[1].passed
    assert v.results[1].failed == 3  # home x2, travel x1


def test_accepted_values_null_handling(spark) -> None:
    df = spark.createDataFrame([("a",), (None,)], ["c"])
    assert DataQualityValidator(df, "t").check_accepted_values("c", ["a"]).results[0].passed
    assert (
        not DataQualityValidator(df, "t")
        .check_accepted_values("c", ["a"], allow_null=False)
        .results[0]
        .passed
    )


def test_row_count_bounds(deduped) -> None:
    v = (
        DataQualityValidator(deduped, "t")
        .check_row_count(min_rows=1, max_rows=10)
        .check_row_count(min_rows=100)
    )
    assert v.results[0].passed and not v.results[1].passed


def test_freshness_with_injected_now(spark) -> None:
    df = spark.createDataFrame([(datetime(2025, 1, 1, 12, 0),)], ["ts"])
    now = datetime(2025, 1, 2, 0, 0, tzinfo=timezone.utc)
    assert (
        DataQualityValidator(df, "t").check_freshness("ts", max_hours=24, now=now).results[0].passed
    )
    assert (
        not DataQualityValidator(df, "t")
        .check_freshness("ts", max_hours=6, now=now)
        .results[0]
        .passed
    )


def test_freshness_empty_column(spark) -> None:
    df = spark.createDataFrame([], "ts TIMESTAMP")
    result = DataQualityValidator(df, "t").check_freshness("ts").results[0]
    assert not result.passed and "no values" in result.details


def test_no_negative_and_value_range(spark) -> None:
    df = spark.createDataFrame([(-1.0,), (5.0,), (50.0,), (None,)], ["amount"])
    v = DataQualityValidator(df, "t")
    v.check_no_negative(["amount"]).check_value_range("amount", min_value=0, max_value=10)
    assert v.results[0].failed == 1
    assert v.results[1].failed == 2  # -1 and 50
    with pytest.raises(ValueError):
        v.check_value_range("amount")


def test_regex(spark) -> None:
    df = spark.createDataFrame([("POL-000001",), ("bad",), (None,)], ["policy_number"])
    result = (
        DataQualityValidator(df, "t").check_regex("policy_number", r"^POL-[0-9]{6}$").results[0]
    )
    assert result.failed == 1
    with pytest.raises(Exception):  # noqa: B017 - invalid pattern must fail fast whatever the re error type
        DataQualityValidator(df, "t").check_regex("policy_number", "(")


def test_check_schema(deduped) -> None:
    v = DataQualityValidator(deduped, "t")
    v.check_schema({"claim_id": "string", "claim_amount": "decimal(18,2)"})
    v.check_schema({"claim_id": "int", "missing_col": "string"})
    v.check_schema({"claim_id": "string"}, strict=True)
    assert v.results[0].passed
    assert v.results[1].failed == 2 and "missing 'missing_col'" in v.results[1].details
    assert not v.results[2].passed  # unexpected extra columns under strict


def test_check_schema_from_struct_type(deduped) -> None:
    assert DataQualityValidator(deduped, "t").check_schema(deduped.schema).results[0].passed


def test_referential_integrity(spark, deduped) -> None:
    policies = spark.createDataFrame(
        [("POL-000001",), ("POL-000002",), ("POL-000003",)], ["policy_number"]
    )
    result = (
        DataQualityValidator(deduped, "t")
        .check_referential_integrity("policy_number", policies, "policy_number")
        .results[0]
    )
    assert result.failed == 3  # POL-000004..6 missing from the reference
    with pytest.raises(ValueError):
        DataQualityValidator(deduped, "t").check_referential_integrity(
            "policy_number", policies, "nope"
        )


def test_custom_condition(deduped) -> None:
    result = (
        DataQualityValidator(deduped, "t").check_custom("positive", "claim_amount > 0").results[0]
    )
    assert result.passed and result.check_type == "custom"


def test_missing_column_raises(deduped) -> None:
    with pytest.raises(ValueError, match="not present"):
        DataQualityValidator(deduped, "t").check_not_null(["ghost"])


def test_invalid_severity_rejected(deduped) -> None:
    with pytest.raises(ValueError):
        DataQualityValidator(deduped, "t").check_not_null(["claim_id"], severity="fatal")


def test_validate_raises_on_blocking_failure(claims_df) -> None:
    v = DataQualityValidator(claims_df, "claims").check_unique(["claim_id"])
    with pytest.raises(DataQualityError) as excinfo:
        v.validate()
    assert "unique:claim_id" in str(excinfo.value)
    assert excinfo.value.summary.failed == 1


def test_warn_severity_does_not_block(claims_df) -> None:
    summary = (
        DataQualityValidator(claims_df, "claims")
        .check_unique(["claim_id"], severity="warn")
        .validate()
    )
    assert summary.ok and summary.warnings == 1 and summary.failed == 0


def test_summary_serialisation(deduped) -> None:
    summary = (
        DataQualityValidator(deduped, "claims")
        .check_not_null(["claim_id"])
        .check_row_count(1)
        .validate()
    )
    payload = json.loads(summary.to_json())
    assert payload["dataset"] == "claims" and payload["total"] == 2 and payload["ok"] is True
    assert payload["results"][0]["check_type"] == "not_null"
    assert "Result: 2/2 passed" in str(summary)
    assert isinstance(CheckResult(**payload["results"][0]), CheckResult)


def test_validate_no_fail_returns_summary(claims_df) -> None:
    summary = (
        DataQualityValidator(claims_df, "c")
        .check_unique(["claim_id"])
        .validate(fail_on_error=False)
    )
    assert not summary.ok


# --------------------------------------------------------------------------- quarantine
def test_split_quarantine(spark) -> None:
    df = spark.createDataFrame(
        [
            ("a", 10.0, "x@example.com"),
            ("b", -5.0, "x@example.com"),
            ("c", 1.0, None),
            ("d", -1.0, None),
        ],
        ["id", "amount", "email"],
    )
    rules = [
        QuarantineRule("non_negative", "amount >= 0"),
        QuarantineRule("has_email", "email IS NOT NULL"),
    ]
    result = split_quarantine(df, rules)
    assert result.counts() == (1, 3)
    failed = {r["id"]: r["_dq_failed_rules"] for r in result.quarantined.collect()}
    assert failed["b"] == ["non_negative"] and failed["c"] == ["has_email"]
    assert failed["d"] == ["non_negative", "has_email"]
    assert "_dq_failed_rules" not in result.valid.columns


def test_split_quarantine_treats_null_predicate_as_failure(spark) -> None:
    df = spark.createDataFrame([(None,), (1.0,)], "amount DOUBLE")
    result = split_quarantine(df, [QuarantineRule("positive", "amount > 0")])
    assert result.counts() == (1, 1)
    assert result.quarantined.filter(F.col("amount").isNull()).count() == 1


def test_quarantine_rule_validation() -> None:
    with pytest.raises(ValueError):
        QuarantineRule("", "x > 0")
