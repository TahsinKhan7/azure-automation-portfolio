"""Silver -> gold aggregation.

Gold tables are consumption-ready: daily operational summaries, monthly trends with
month-on-month change and rolling averages, and a one-row KPI snapshot. The datasets are
produced by :func:`build_gold_datasets` (pure) and persisted by :func:`run_silver_to_gold`.
"""

from __future__ import annotations

import logging
import uuid
from collections.abc import Sequence
from dataclasses import dataclass

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F

from dataplatform.etl import aggregations as A
from dataplatform.etl.writers import DELTA, write_table

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class GoldConfig:
    """Which columns drive the gold aggregations for a dataset."""

    date_column: str
    value_column: str
    group_columns: Sequence[str] = ()
    rolling_window: int = 3

    def __post_init__(self) -> None:
        if not self.date_column or not self.value_column:
            raise ValueError("date_column and value_column are required for gold aggregations")


def build_gold_datasets(
    df: DataFrame, config: GoldConfig, run_id: str | None = None
) -> dict[str, DataFrame]:
    """Return the gold DataFrames keyed by table name."""
    stamp = {"_aggregated_at": F.current_timestamp(), "_run_id": F.lit(run_id)}
    return {
        "daily_summary": A.daily_summary(
            df, config.date_column, config.group_columns, config.value_column
        ).withColumns(stamp),
        "monthly_trends": A.monthly_trends(
            df,
            config.date_column,
            config.group_columns,
            config.value_column,
            rolling_window=config.rolling_window,
        ).withColumns(stamp),
        "kpi_snapshot": A.kpi_snapshot(
            df, config.date_column, config.value_column, config.group_columns
        ).withColumn("_run_id", F.lit(run_id)),
    }


def run_silver_to_gold(
    spark: SparkSession,
    silver_path: str,
    gold_base_path: str,
    config: GoldConfig,
    fmt: str = DELTA,
    run_id: str | None = None,
) -> dict[str, int]:
    """Read silver, build every gold dataset and overwrite them under ``gold_base_path``.

    Returns:
        Row counts written per gold table.
    """
    run_id = run_id or uuid.uuid4().hex
    logger.info("[%s] silver -> gold starting: %s", run_id, silver_path)
    silver = spark.read.format(fmt).load(silver_path)

    counts: dict[str, int] = {}
    for name, frame in build_gold_datasets(silver, config, run_id=run_id).items():
        target = f"{gold_base_path.rstrip('/')}/{name}/"
        partition_by = ["report_date"] if name == "daily_summary" else None
        write_table(
            frame,
            target,
            fmt=fmt,
            mode="overwrite",
            partition_by=partition_by,
            overwrite_schema=True,
        )
        counts[name] = spark.read.format(fmt).load(target).count()
        logger.info("[%s] gold.%s written (%d rows)", run_id, name, counts[name])
    return counts
