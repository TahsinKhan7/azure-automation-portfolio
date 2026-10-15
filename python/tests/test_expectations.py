from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from dataplatform.quality.expectations import (
    SUPPORTED_TYPES,
    Expectation,
    ExpectationSuite,
    load_suite,
    run_suite,
    run_suite_from_file,
)
from dataplatform.quality.validator import DataQualityError


@pytest.mark.parametrize(
    "name", ["claims_silver.yml", "policies_silver.yml", "customers_silver.yml"]
)
def test_shipped_suites_load(config_dir: Path, name: str) -> None:
    suite = load_suite(config_dir / "quality" / name)
    assert suite.expectations
    assert all(e.type in SUPPORTED_TYPES for e in suite.expectations)


def test_load_suite_parses_severity(config_dir: Path) -> None:
    suite = load_suite(config_dir / "quality" / "claims_silver.yml")
    freshness = next(e for e in suite.expectations if e.type == "freshness")
    assert freshness.severity == "warn" and freshness.params["max_hours"] == 48


def test_unsupported_type_rejected() -> None:
    with pytest.raises(ValueError, match="Unsupported expectation type"):
        Expectation(type="is_awesome")


def test_suite_validation() -> None:
    with pytest.raises(ValueError, match="dataset"):
        ExpectationSuite.from_mapping({"expectations": []})
    with pytest.raises(ValueError, match="no expectations"):
        ExpectationSuite.from_mapping({"dataset": "x", "expectations": []})
    with pytest.raises(ValueError, match="without 'type'"):
        ExpectationSuite.from_mapping({"dataset": "x", "expectations": [{"columns": ["a"]}]})


def test_missing_file() -> None:
    with pytest.raises(FileNotFoundError):
        load_suite("/nonexistent/suite.yml")


@pytest.mark.spark
def test_run_claims_suite_against_conformed_data(spark, claims_df, config_dir: Path) -> None:
    from dataplatform.etl import transforms as T

    silver = T.deduplicate_latest(claims_df, ["claim_id"], "_ingested_at")
    silver = T.add_audit_columns(silver, "1.0")
    summary = run_suite_from_file(silver, config_dir / "quality" / "claims_silver.yml")
    assert summary.ok and summary.failed == 0
    assert {r.check_type for r in summary.results} >= {
        "schema",
        "unique",
        "regex",
        "value_range",
        "freshness",
    }


@pytest.mark.spark
def test_run_suite_fails_on_duplicates(claims_df, config_dir: Path) -> None:
    suite = load_suite(config_dir / "quality" / "claims_silver.yml")
    with pytest.raises(DataQualityError):
        run_suite(claims_df.withColumn("_processed_at", claims_df["_ingested_at"]), suite)


@pytest.mark.spark
def test_referential_integrity_expectation(spark, claims_df, tmp_path: Path) -> None:
    suite_file = tmp_path / "suite.yml"
    suite_file.write_text(
        yaml.safe_dump(
            {
                "dataset": "claims",
                "expectations": [
                    {
                        "type": "referential_integrity",
                        "column": "policy_number",
                        "reference": "policies",
                        "reference_column": "policy_number",
                    },
                    {"type": "custom", "name": "positive", "condition": "claim_amount > 0"},
                ],
            }
        )
    )
    policies = claims_df.select("policy_number").distinct()
    summary = run_suite_from_file(claims_df, suite_file, reference_frames={"policies": policies})
    assert summary.ok
    with pytest.raises(ValueError, match="reference frame"):
        run_suite(claims_df, load_suite(suite_file))
