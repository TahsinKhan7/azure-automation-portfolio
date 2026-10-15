"""Gold-layer aggregations: daily summaries, monthly totals, MoM change and rolling averages.

All functions are pure DataFrame transforms built on ``groupBy`` and window functions.
"""

from __future__ import annotations

from collections.abc import Sequence

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.window import Window


def daily_summary(
    df: DataFrame,
    date_column: str,
    group_columns: Sequence[str],
    value_column: str,
) -> DataFrame:
    """Per-day operational metrics: counts and basic statistics of ``value_column``."""
    return (
        df.withColumn("report_date", F.to_date(F.col(date_column)))
        .groupBy("report_date", *group_columns)
        .agg(
            F.count(F.lit(1)).alias("record_count"),
            F.sum(value_column).alias("total_value"),
            F.avg(value_column).alias("avg_value"),
            F.min(value_column).alias("min_value"),
            F.max(value_column).alias("max_value"),
            F.stddev_samp(value_column).alias("stddev_value"),
        )
    )


def monthly_totals(
    df: DataFrame,
    date_column: str,
    group_columns: Sequence[str],
    value_column: str,
) -> DataFrame:
    """Aggregate to ``year_month`` x ``group_columns`` with volume and value totals."""
    return (
        df.withColumn("year_month", F.date_format(F.col(date_column), "yyyy-MM"))
        .groupBy("year_month", *group_columns)
        .agg(
            F.count(F.lit(1)).alias("volume"),
            F.sum(value_column).alias("total_value"),
            F.avg(value_column).alias("avg_value"),
        )
    )


def add_mom_change(
    df: DataFrame,
    partition_columns: Sequence[str],
    order_column: str = "year_month",
    value_column: str = "total_value",
) -> DataFrame:
    """Add previous-period value, absolute change and percentage change columns.

    Percentage change is null for the first period and when the previous value is zero,
    rather than producing an infinite or misleading number.
    """
    window = Window.partitionBy(*partition_columns).orderBy(order_column)
    previous = F.lag(F.col(value_column)).over(window)
    return (
        df.withColumn("previous_value", previous)
        .withColumn("mom_change", F.col(value_column) - F.col("previous_value"))
        .withColumn(
            "mom_change_pct",
            F.when(
                F.col("previous_value").isNotNull() & (F.col("previous_value") != 0),
                F.round(
                    (F.col(value_column) - F.col("previous_value"))
                    / F.abs(F.col("previous_value"))
                    * 100,
                    2,
                ),
            ),
        )
    )


def add_rolling_average(
    df: DataFrame,
    partition_columns: Sequence[str],
    order_column: str = "year_month",
    value_column: str = "total_value",
    window_size: int = 3,
    output_column: str | None = None,
) -> DataFrame:
    """Add a trailing ``window_size``-period moving average of ``value_column``.

    The window is row based (``window_size - 1`` preceding rows plus the current row), so
    the first periods average over fewer rows rather than returning null.
    """
    if window_size < 1:
        raise ValueError("window_size must be at least 1")
    name = output_column or f"rolling_avg_{window_size}"
    window = (
        Window.partitionBy(*partition_columns)
        .orderBy(order_column)
        .rowsBetween(-(window_size - 1), Window.currentRow)
    )
    return df.withColumn(name, F.round(F.avg(F.col(value_column)).over(window), 4))


def monthly_trends(
    df: DataFrame,
    date_column: str,
    group_columns: Sequence[str],
    value_column: str,
    rolling_window: int = 3,
) -> DataFrame:
    """Monthly totals enriched with MoM change and a rolling average, ready for reporting."""
    monthly = monthly_totals(df, date_column, group_columns, value_column)
    monthly = add_mom_change(monthly, group_columns)
    monthly = add_rolling_average(monthly, group_columns, window_size=rolling_window)
    return monthly.orderBy("year_month", *group_columns)


def kpi_snapshot(
    df: DataFrame,
    date_column: str,
    value_column: str,
    distinct_count_columns: Sequence[str] = (),
) -> DataFrame:
    """Single-row KPI snapshot for dashboard tiles."""
    aggregates = [
        F.count(F.lit(1)).alias("total_records"),
        F.sum(value_column).alias("total_value"),
        F.avg(value_column).alias("average_value"),
        F.min(date_column).alias("earliest_record"),
        F.max(date_column).alias("latest_record"),
    ]
    aggregates.extend(
        F.countDistinct(col).alias(f"distinct_{col}") for col in distinct_count_columns
    )
    return df.agg(*aggregates).withColumn("_snapshot_at", F.current_timestamp())
