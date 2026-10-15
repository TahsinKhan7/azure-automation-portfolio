"""YAML-driven expectation suites.

A suite is a list of expectations such as::

    dataset: claims_silver
    expectations:
      - type: not_null
        columns: [claim_id]
      - type: value_range
        column: claim_amount
        min: 0
        severity: warn

Keeping expectations in YAML lets analysts own the rules without touching Python and lets
the same suite run from a notebook, a job task or the CLI.
"""

from __future__ import annotations

import logging
import os
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml
from pyspark.sql import DataFrame

from dataplatform.quality.validator import DataQualityValidator, ValidationSummary

logger = logging.getLogger(__name__)

SUPPORTED_TYPES = (
    "not_null",
    "unique",
    "accepted_values",
    "row_count",
    "freshness",
    "no_negative",
    "value_range",
    "regex",
    "schema",
    "referential_integrity",
    "custom",
)


@dataclass(frozen=True)
class Expectation:
    """One rule from a suite."""

    type: str
    params: dict[str, Any] = field(default_factory=dict)
    severity: str = "error"

    def __post_init__(self) -> None:
        if self.type not in SUPPORTED_TYPES:
            raise ValueError(
                f"Unsupported expectation type '{self.type}'; expected one of {SUPPORTED_TYPES}"
            )


@dataclass(frozen=True)
class ExpectationSuite:
    """A named set of expectations for one dataset."""

    dataset: str
    expectations: list[Expectation]
    description: str = ""

    @classmethod
    def from_mapping(cls, raw: Mapping[str, Any]) -> ExpectationSuite:
        if "dataset" not in raw:
            raise ValueError("Expectation suite must declare 'dataset'")
        items = raw.get("expectations") or []
        if not isinstance(items, list) or not items:
            raise ValueError(f"Suite '{raw['dataset']}' has no expectations")
        expectations = []
        for item in items:
            item = dict(item)
            etype = item.pop("type", None)
            if not etype:
                raise ValueError(f"Expectation without 'type' in suite '{raw['dataset']}': {item}")
            severity = item.pop("severity", "error")
            expectations.append(Expectation(type=etype, params=item, severity=severity))
        return cls(
            dataset=str(raw["dataset"]),
            expectations=expectations,
            description=str(raw.get("description", "")),
        )


def load_suite(path: str | os.PathLike[str]) -> ExpectationSuite:
    """Load a suite from a YAML file."""
    file = Path(path)
    if not file.is_file():
        raise FileNotFoundError(f"Expectation suite not found: {file}")
    with file.open("r", encoding="utf-8") as handle:
        raw = yaml.safe_load(handle) or {}
    suite = ExpectationSuite.from_mapping(raw)
    logger.info(
        "Loaded suite '%s' with %d expectation(s) from %s",
        suite.dataset,
        len(suite.expectations),
        file,
    )
    return suite


def run_suite(
    df: DataFrame,
    suite: ExpectationSuite,
    reference_frames: Mapping[str, DataFrame] | None = None,
    fail_on_error: bool = True,
) -> ValidationSummary:
    """Execute every expectation in ``suite`` against ``df``.

    Args:
        reference_frames: Named DataFrames for ``referential_integrity`` expectations, keyed
            by the ``reference`` value in the YAML.
    """
    validator = DataQualityValidator(df, suite.dataset)
    for expectation in suite.expectations:
        _apply(validator, expectation, reference_frames or {})
    return validator.validate(fail_on_error=fail_on_error)


def run_suite_from_file(
    df: DataFrame,
    path: str | os.PathLike[str],
    reference_frames: Mapping[str, DataFrame] | None = None,
    fail_on_error: bool = True,
) -> ValidationSummary:
    """Convenience wrapper: :func:`load_suite` then :func:`run_suite`."""
    return run_suite(df, load_suite(path), reference_frames, fail_on_error)


def _apply(
    validator: DataQualityValidator, exp: Expectation, refs: Mapping[str, DataFrame]
) -> None:
    p = exp.params
    sev = exp.severity
    if exp.type == "not_null":
        validator.check_not_null(list(p["columns"]), severity=sev)
    elif exp.type == "unique":
        validator.check_unique(list(p["columns"]), severity=sev)
    elif exp.type == "accepted_values":
        validator.check_accepted_values(
            p["column"], list(p["values"]), allow_null=p.get("allow_null", True), severity=sev
        )
    elif exp.type == "row_count":
        validator.check_row_count(
            min_rows=int(p.get("min", 1)), max_rows=p.get("max"), severity=sev
        )
    elif exp.type == "freshness":
        validator.check_freshness(
            p["column"], max_hours=float(p.get("max_hours", 24)), severity=sev
        )
    elif exp.type == "no_negative":
        validator.check_no_negative(list(p["columns"]), severity=sev)
    elif exp.type == "value_range":
        validator.check_value_range(
            p["column"], min_value=p.get("min"), max_value=p.get("max"), severity=sev
        )
    elif exp.type == "regex":
        validator.check_regex(p["column"], str(p["pattern"]), severity=sev)
    elif exp.type == "schema":
        validator.check_schema(
            {k: str(v) for k, v in p["columns"].items()},
            strict=bool(p.get("strict", False)),
            severity=sev,
        )
    elif exp.type == "referential_integrity":
        ref_name = p["reference"]
        if ref_name not in refs:
            raise ValueError(
                f"referential_integrity expectation needs reference frame '{ref_name}'"
            )
        validator.check_referential_integrity(
            p["column"], refs[ref_name], p["reference_column"], severity=sev
        )
    elif exp.type == "custom":
        validator.check_custom(p["name"], p["condition"], severity=sev)
