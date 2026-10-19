"""OPTIMIZE / ZORDER / VACUUM runner for Delta tables.

Maintenance is gated by an explicit allow-list so a misconfigured job cannot vacuum a table
it was never meant to touch, and ``dry_run`` returns the SQL it would run without executing.
"""

from __future__ import annotations

import logging
import re
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from typing import Any

from pyspark.sql import SparkSession

logger = logging.getLogger(__name__)

_IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*){0,2}$")
_PATH = re.compile(r"^(abfss|s3a?|gs|dbfs|file)://.+|^/.+")
MIN_SAFE_RETENTION_HOURS = 168


@dataclass(frozen=True)
class MaintenanceTask:
    """One table and what to do to it."""

    table: str
    zorder_by: Sequence[str] = ()
    vacuum_retention_hours: int | None = MIN_SAFE_RETENTION_HOURS
    optimize_where: str | None = None


@dataclass
class MaintenanceOutcome:
    table: str
    statements: list[str] = field(default_factory=list)
    executed: bool = False
    error: str | None = None


def table_reference(table: str) -> str:
    """Return ``name`` for identifiers or ``delta.`path``` for storage paths."""
    if _IDENTIFIER.match(table):
        return table
    if _PATH.match(table):
        return f"delta.`{table}`"
    raise ValueError(f"'{table}' is neither a table identifier nor a storage path")


def build_statements(task: MaintenanceTask) -> list[str]:
    """Render the SQL for a task (pure; used by dry-run and tests)."""
    ref = table_reference(task.table)
    statements = []
    optimize = f"OPTIMIZE {ref}"
    if task.optimize_where:
        optimize += f" WHERE {task.optimize_where}"
    if task.zorder_by:
        optimize += f" ZORDER BY ({', '.join(task.zorder_by)})"
    statements.append(optimize)
    if task.vacuum_retention_hours is not None:
        if task.vacuum_retention_hours < 0:
            raise ValueError("vacuum_retention_hours must be >= 0")
        statements.append(f"VACUUM {ref} RETAIN {int(task.vacuum_retention_hours)} HOURS")
    return statements


class DeltaMaintenanceRunner:
    """Run maintenance tasks against an allow-list of tables.

    Args:
        spark: Active SparkSession.
        allow_list: Tables (identifiers or paths) that may be maintained. Tasks for any other
            table are refused.
        dry_run: Only render the statements.
        allow_short_retention: Permit VACUUM below the 7-day safety threshold (requires the
            corresponding Spark config to be disabled as well).
    """

    def __init__(
        self,
        spark: SparkSession,
        allow_list: Iterable[str],
        dry_run: bool = True,
        allow_short_retention: bool = False,
    ):
        self.spark = spark
        self.allow_list = frozenset(allow_list)
        self.dry_run = dry_run
        self.allow_short_retention = allow_short_retention

    def check_allowed(self, task: MaintenanceTask) -> None:
        if task.table not in self.allow_list:
            raise PermissionError(f"Table '{task.table}' is not on the maintenance allow-list")
        retention = task.vacuum_retention_hours
        if (
            retention is not None
            and retention < MIN_SAFE_RETENTION_HOURS
            and not self.allow_short_retention
        ):
            raise ValueError(
                f"VACUUM retention {retention}h for '{task.table}' is below the "
                f"{MIN_SAFE_RETENTION_HOURS}h safety threshold; set allow_short_retention=True "
                "to override deliberately"
            )

    def run_task(self, task: MaintenanceTask) -> MaintenanceOutcome:
        outcome = MaintenanceOutcome(task.table)
        try:
            self.check_allowed(task)
            outcome.statements = build_statements(task)
            for statement in outcome.statements:
                if self.dry_run:
                    logger.info("[dry-run] %s", statement)
                else:
                    logger.info("Executing: %s", statement)
                    self.spark.sql(statement)
            outcome.executed = not self.dry_run
        except (PermissionError, ValueError) as exc:
            outcome.error = str(exc)
            logger.error("Skipping %s: %s", task.table, exc)
        return outcome

    def run(self, tasks: Sequence[MaintenanceTask]) -> list[MaintenanceOutcome]:
        outcomes = [self.run_task(task) for task in tasks]
        done = sum(1 for o in outcomes if o.executed)
        errors = sum(1 for o in outcomes if o.error)
        logger.info(
            "Maintenance finished: %d executed, %d skipped, dry_run=%s", done, errors, self.dry_run
        )
        return outcomes

    def table_detail(self, table: str) -> dict[str, Any]:
        """``DESCRIBE DETAIL`` as a dict (file count, size, partitions) for before/after logging."""
        row = self.spark.sql(f"DESCRIBE DETAIL {table_reference(table)}").first()
        return row.asDict() if row else {}
