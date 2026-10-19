"""Row-level quarantine: split a DataFrame into rows that satisfy every rule and rows that do not.

Where the validator answers "is this dataset fit to promote?", the quarantine helper answers
"which rows are the problem?" so that good rows can flow on while bad rows are parked with
a reason for triage.
"""

from __future__ import annotations

import logging
from collections.abc import Sequence
from dataclasses import dataclass

from pyspark.sql import DataFrame
from pyspark.sql import functions as F

logger = logging.getLogger(__name__)

FAILED_RULES_COLUMN = "_dq_failed_rules"


@dataclass(frozen=True)
class QuarantineRule:
    """A named SQL predicate that every valid row must satisfy."""

    name: str
    condition: str

    def __post_init__(self) -> None:
        if not self.name or not self.condition:
            raise ValueError("QuarantineRule requires a name and a condition")


@dataclass(frozen=True)
class QuarantineResult:
    """Valid and quarantined DataFrames (quarantined rows carry ``_dq_failed_rules``)."""

    valid: DataFrame
    quarantined: DataFrame

    def counts(self) -> tuple[int, int]:
        return self.valid.count(), self.quarantined.count()


def split_quarantine(df: DataFrame, rules: Sequence[QuarantineRule]) -> QuarantineResult:
    """Apply ``rules`` row by row.

    A row is quarantined when any rule evaluates to false or null (a null predicate, for
    example a comparison against a null value, is treated as a failure, which is the safe
    default for a quality gate).
    """
    if not rules:
        raise ValueError("At least one QuarantineRule is required")
    flags = [
        F.when(F.coalesce(F.expr(rule.condition), F.lit(False)), F.lit(None)).otherwise(
            F.lit(rule.name)
        )
        for rule in rules
    ]
    tagged = df.withColumn(FAILED_RULES_COLUMN, F.array_compact(F.array(*flags)))
    valid = tagged.filter(F.size(FAILED_RULES_COLUMN) == 0).drop(FAILED_RULES_COLUMN)
    quarantined = tagged.filter(F.size(FAILED_RULES_COLUMN) > 0).withColumn(
        "_quarantined_at", F.current_timestamp()
    )
    logger.info("Quarantine split applied with %d rule(s)", len(rules))
    return QuarantineResult(valid=valid, quarantined=quarantined)
