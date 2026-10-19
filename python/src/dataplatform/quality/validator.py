"""Data quality validator used as a gate between medallion layers.

Checks are chained fluently, results are plain dataclasses (serialisable to JSON for run
logs or a metadata table) and ``validate()`` raises :class:`DataQualityError` when any check
with ``severity="error"`` fails. ``severity="warn"`` checks are reported but never block.
"""

from __future__ import annotations

import json
import logging
import re
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import StructType

logger = logging.getLogger(__name__)

SEVERITIES = ("error", "warn")


@dataclass(frozen=True)
class CheckResult:
    """Outcome of a single check."""

    name: str
    check_type: str
    passed: bool
    checked: int
    failed: int
    details: str
    severity: str = "error"

    @property
    def blocking(self) -> bool:
        return not self.passed and self.severity == "error"

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class ValidationSummary:
    """Aggregate view of a validation run."""

    dataset: str
    row_count: int
    results: list[CheckResult] = field(default_factory=list)
    validated_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())

    @property
    def total(self) -> int:
        return len(self.results)

    @property
    def passed(self) -> int:
        return sum(1 for r in self.results if r.passed)

    @property
    def failed(self) -> int:
        return sum(1 for r in self.results if r.blocking)

    @property
    def warnings(self) -> int:
        return sum(1 for r in self.results if not r.passed and r.severity == "warn")

    @property
    def ok(self) -> bool:
        return self.failed == 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "dataset": self.dataset,
            "row_count": self.row_count,
            "validated_at": self.validated_at,
            "total": self.total,
            "passed": self.passed,
            "failed": self.failed,
            "warnings": self.warnings,
            "ok": self.ok,
            "results": [r.to_dict() for r in self.results],
        }

    def to_json(self, indent: int | None = 2) -> str:
        return json.dumps(self.to_dict(), indent=indent, default=str)

    def __str__(self) -> str:
        lines = [f"Data quality: {self.dataset} ({self.row_count} rows)"]
        for r in self.results:
            status = "PASS" if r.passed else ("WARN" if r.severity == "warn" else "FAIL")
            lines.append(f"  [{status}] {r.name}: {r.details}")
        lines.append(
            f"Result: {self.passed}/{self.total} passed, {self.failed} failed, "
            f"{self.warnings} warnings"
        )
        return "\n".join(lines)


class DataQualityError(RuntimeError):
    """Raised when a validation run has blocking failures."""

    def __init__(self, summary: ValidationSummary):
        self.summary = summary
        failed = [r.name for r in summary.results if r.blocking]
        super().__init__(
            f"Data quality gate failed for '{summary.dataset}': {summary.failed} blocking "
            f"check(s) failed: {', '.join(failed)}"
        )


class DataQualityValidator:
    """Fluent validator over a single DataFrame.

    Example::

        summary = (
            DataQualityValidator(df, "claims_silver")
            .check_not_null(["claim_id"])
            .check_unique(["claim_id"])
            .check_value_range("claim_amount", min_value=0)
            .validate()
        )
    """

    def __init__(self, df: DataFrame, dataset_name: str):
        self.df = df
        self.dataset_name = dataset_name
        self.results: list[CheckResult] = []
        self._count: int | None = None

    # ------------------------------------------------------------------ helpers
    @property
    def count(self) -> int:
        if self._count is None:
            self._count = self.df.count()
        return self._count

    def _record(
        self,
        name: str,
        check_type: str,
        failed: int,
        details: str,
        severity: str,
        checked: int | None = None,
        passed: bool | None = None,
    ) -> DataQualityValidator:
        if severity not in SEVERITIES:
            raise ValueError(f"severity must be one of {SEVERITIES}, got '{severity}'")
        result = CheckResult(
            name=name,
            check_type=check_type,
            passed=(failed == 0) if passed is None else passed,
            checked=self.count if checked is None else checked,
            failed=failed,
            details=details,
            severity=severity,
        )
        self.results.append(result)
        logger.log(
            logging.INFO if result.passed else logging.WARNING,
            "[%s] %s: %s",
            self.dataset_name,
            name,
            details,
        )
        return self

    def _require_columns(self, columns: Iterable[str]) -> None:
        missing = [c for c in columns if c not in self.df.columns]
        if missing:
            raise ValueError(f"Columns not present in '{self.dataset_name}': {missing}")

    # ------------------------------------------------------------------- checks
    def check_not_null(
        self, columns: Sequence[str], severity: str = "error"
    ) -> DataQualityValidator:
        """Each column must contain no nulls."""
        self._require_columns(columns)
        for col in columns:
            nulls = self.df.filter(F.col(col).isNull()).count()
            self._record(
                f"not_null:{col}",
                "not_null",
                nulls,
                f"{nulls}/{self.count} null in '{col}'",
                severity,
            )
        return self

    def check_unique(self, columns: Sequence[str], severity: str = "error") -> DataQualityValidator:
        """The combination of ``columns`` must be unique across rows."""
        self._require_columns(columns)
        distinct = self.df.select(*columns).distinct().count()
        dupes = self.count - distinct
        return self._record(
            f"unique:{','.join(columns)}",
            "unique",
            dupes,
            f"{dupes} duplicate row(s) across {list(columns)}",
            severity,
        )

    def check_accepted_values(
        self,
        column: str,
        accepted: Sequence[Any],
        allow_null: bool = True,
        severity: str = "error",
    ) -> DataQualityValidator:
        """Values in ``column`` must be within ``accepted``."""
        self._require_columns([column])
        condition = ~F.col(column).isin(list(accepted))
        if allow_null:
            condition = condition & F.col(column).isNotNull()
        else:
            condition = condition | F.col(column).isNull()
        invalid = self.df.filter(condition).count()
        return self._record(
            f"accepted_values:{column}",
            "accepted_values",
            invalid,
            f"{invalid} value(s) in '{column}' outside {list(accepted)}",
            severity,
        )

    def check_row_count(
        self, min_rows: int = 1, max_rows: int | None = None, severity: str = "error"
    ) -> DataQualityValidator:
        """Row count must fall within ``[min_rows, max_rows]``."""
        ok = self.count >= min_rows and (max_rows is None or self.count <= max_rows)
        return self._record(
            "row_count",
            "row_count",
            0 if ok else 1,
            f"{self.count} rows (expected {min_rows}..{'inf' if max_rows is None else max_rows})",
            severity,
            passed=ok,
        )

    def check_freshness(
        self,
        timestamp_column: str,
        max_hours: float = 24,
        now: datetime | None = None,
        severity: str = "error",
    ) -> DataQualityValidator:
        """The newest value in ``timestamp_column`` must be within ``max_hours`` of now."""
        self._require_columns([timestamp_column])
        latest = self.df.agg(F.max(timestamp_column)).first()[0]
        if latest is None:
            return self._record(
                f"freshness:{timestamp_column}",
                "freshness",
                1,
                f"no values in '{timestamp_column}'",
                severity,
                passed=False,
            )
        if not isinstance(latest, datetime):
            latest = datetime.combine(latest, datetime.min.time())
        reference = now or datetime.now(timezone.utc)
        if latest.tzinfo is None:
            reference = reference.replace(tzinfo=None)
        age_hours = (reference - latest).total_seconds() / 3600
        ok = age_hours <= max_hours
        return self._record(
            f"freshness:{timestamp_column}",
            "freshness",
            0 if ok else 1,
            f"latest {latest.isoformat()} is {age_hours:.1f}h old (max {max_hours}h)",
            severity,
            passed=ok,
        )

    def check_no_negative(
        self, columns: Sequence[str], severity: str = "error"
    ) -> DataQualityValidator:
        """Numeric columns must not contain negative values."""
        self._require_columns(columns)
        for col in columns:
            negatives = self.df.filter(F.col(col) < 0).count()
            self._record(
                f"no_negative:{col}",
                "no_negative",
                negatives,
                f"{negatives} negative value(s) in '{col}'",
                severity,
            )
        return self

    def check_value_range(
        self,
        column: str,
        min_value: float | None = None,
        max_value: float | None = None,
        severity: str = "error",
    ) -> DataQualityValidator:
        """Non-null values in ``column`` must lie within ``[min_value, max_value]``."""
        if min_value is None and max_value is None:
            raise ValueError("Provide min_value and/or max_value")
        self._require_columns([column])
        condition = F.lit(False)
        if min_value is not None:
            condition = condition | (F.col(column) < F.lit(min_value))
        if max_value is not None:
            condition = condition | (F.col(column) > F.lit(max_value))
        out_of_range = self.df.filter(condition).count()
        return self._record(
            f"value_range:{column}",
            "value_range",
            out_of_range,
            f"{out_of_range} value(s) in '{column}' outside [{min_value}, {max_value}]",
            severity,
        )

    def check_regex(
        self, column: str, pattern: str, severity: str = "error"
    ) -> DataQualityValidator:
        """Non-null values in ``column`` must match ``pattern`` (Java regex, partial match)."""
        re.compile(pattern)  # fail fast on an invalid pattern
        self._require_columns([column])
        mismatched = self.df.filter(
            F.col(column).isNotNull() & ~F.col(column).rlike(pattern)
        ).count()
        return self._record(
            f"regex:{column}",
            "regex",
            mismatched,
            f"{mismatched} value(s) in '{column}' do not match /{pattern}/",
            severity,
        )

    def check_schema(
        self,
        expected: Mapping[str, str] | StructType,
        strict: bool = False,
        severity: str = "error",
    ) -> DataQualityValidator:
        """Columns in ``expected`` must exist with the given Spark type.

        Args:
            expected: ``{"claim_id": "string", "claim_amount": "decimal(18,2)"}`` or a
                StructType.
            strict: Also fail when the DataFrame has columns that are not in ``expected``.
        """
        if isinstance(expected, StructType):
            expected = {f.name: f.dataType.simpleString() for f in expected.fields}
        actual = {f.name: f.dataType.simpleString() for f in self.df.schema.fields}
        problems: list[str] = []
        for name, dtype in expected.items():
            if name not in actual:
                problems.append(f"missing '{name}'")
            elif actual[name] != dtype.lower().replace(" ", ""):
                problems.append(f"'{name}' is {actual[name]}, expected {dtype}")
        if strict:
            problems.extend(f"unexpected '{name}'" for name in actual if name not in expected)
        details = "; ".join(problems) if problems else f"{len(expected)} column(s) match"
        return self._record(
            "schema", "schema", len(problems), details, severity, checked=len(expected)
        )

    def check_referential_integrity(
        self,
        column: str,
        reference: DataFrame,
        reference_column: str,
        severity: str = "error",
    ) -> DataQualityValidator:
        """Every non-null value in ``column`` must exist in ``reference[reference_column]``."""
        self._require_columns([column])
        if reference_column not in reference.columns:
            raise ValueError(f"Column '{reference_column}' not present in reference DataFrame")
        orphans = (
            self.df.filter(F.col(column).isNotNull())
            .select(F.col(column).alias("_fk"))
            .join(
                reference.select(F.col(reference_column).alias("_fk")).distinct(),
                on="_fk",
                how="left_anti",
            )
            .count()
        )
        return self._record(
            f"referential_integrity:{column}",
            "referential_integrity",
            orphans,
            f"{orphans} value(s) in '{column}' not found in reference '{reference_column}'",
            severity,
        )

    def check_custom(
        self, name: str, condition: str, severity: str = "error"
    ) -> DataQualityValidator:
        """Rows must satisfy the SQL ``condition`` (e.g. ``"end_date >= start_date"``)."""
        failing = self.df.filter(~F.expr(condition)).count()
        return self._record(
            f"custom:{name}", "custom", failing, f"{failing} row(s) violate '{condition}'", severity
        )

    # ------------------------------------------------------------------ results
    def summary(self) -> ValidationSummary:
        return ValidationSummary(self.dataset_name, self.count, list(self.results))

    def validate(self, fail_on_error: bool = True) -> ValidationSummary:
        """Return the summary, raising :class:`DataQualityError` on blocking failures."""
        summary = self.summary()
        logger.info("%s", summary)
        if fail_on_error and not summary.ok:
            raise DataQualityError(summary)
        return summary
