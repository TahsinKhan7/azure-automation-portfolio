"""Thin write helpers so every layer uses the same Delta conventions."""

from __future__ import annotations

import logging
from collections.abc import Sequence

from pyspark.sql import DataFrame

logger = logging.getLogger(__name__)

DELTA = "delta"


def write_table(
    df: DataFrame,
    path: str,
    fmt: str = DELTA,
    mode: str = "overwrite",
    partition_by: Sequence[str] | None = None,
    merge_schema: bool = True,
    overwrite_schema: bool = False,
    replace_where: str | None = None,
) -> None:
    """Write ``df`` to ``path``.

    Args:
        fmt: ``delta`` in production; tests may pass ``parquet``.
        mode: ``overwrite`` or ``append``.
        partition_by: Partition columns (Hive-style for parquet, Delta partitions for delta).
        merge_schema: Allow additive schema evolution on Delta appends/overwrites.
        overwrite_schema: Allow destructive schema changes (type changes, drops) on overwrite.
        replace_where: Delta predicate for a partial, idempotent overwrite, e.g.
            ``"year = 2025 AND month = 3"``.
    """
    writer = df.write.format(fmt).mode(mode)
    if partition_by:
        writer = writer.partitionBy(*partition_by)
    if fmt == DELTA:
        if merge_schema:
            writer = writer.option("mergeSchema", "true")
        if overwrite_schema:
            writer = writer.option("overwriteSchema", "true")
        if replace_where:
            writer = writer.option("replaceWhere", replace_where)
    logger.info(
        "Writing %s (mode=%s, partitions=%s) -> %s", fmt, mode, list(partition_by or []), path
    )
    writer.save(path)
