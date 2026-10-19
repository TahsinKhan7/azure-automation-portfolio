"""Bronze -> silver conformance.

Silver is the first layer with business meaning: stable column names, declared types,
one row per business key, sentinel nulls removed and audit columns in place. The
transformation itself (:func:`transform_bronze_to_silver`) is a pure function so it can be
tested without touching storage.
"""

from __future__ import annotations

import logging
import uuid
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field

from pyspark.sql import DataFrame, SparkSession

from dataplatform.etl import transforms as T
from dataplatform.etl.writers import DELTA, write_table

logger = logging.getLogger(__name__)

ETL_VERSION = "2.0"


@dataclass(frozen=True)
class SilverConfig:
    """How to conform one dataset."""

    key_columns: Sequence[str]
    order_column: str | None = "_ingested_at"
    date_column: str | None = None
    partition_columns: Sequence[str] = ()
    cast_schema: Mapping[str, str] = field(default_factory=dict)
    null_default: str | None = None
    null_token_columns: Sequence[str] | None = None
    etl_version: str = ETL_VERSION

    def __post_init__(self) -> None:
        if not self.key_columns:
            raise ValueError("key_columns must not be empty")


@dataclass(frozen=True)
class LayerResult:
    """Outcome of one layer run."""

    run_id: str
    rows_in: int
    rows_out: int
    target_path: str

    @property
    def rows_dropped(self) -> int:
        return self.rows_in - self.rows_out


def transform_bronze_to_silver(
    df: DataFrame, config: SilverConfig, run_id: str | None = None
) -> DataFrame:
    """Apply the full bronze -> silver conformance pipeline to ``df``.

    Steps, in order: normalise column names, standardise sentinel nulls, cast declared
    types, deduplicate to the latest record per key, derive period columns from the
    business date (used for partitioning) and add audit columns.
    """
    out = T.clean_column_names(df)
    out = T.standardise_nulls(out, columns=config.null_token_columns, default=config.null_default)
    if config.cast_schema:
        out = T.cast_schema(out, config.cast_schema)
    out = T.deduplicate_latest(out, config.key_columns, config.order_column)
    if config.date_column:
        out = T.derive_period_columns(out, config.date_column)
    return T.add_audit_columns(out, etl_version=config.etl_version, run_id=run_id)


def run_bronze_to_silver(
    spark: SparkSession,
    source_path: str,
    target_path: str,
    config: SilverConfig,
    fmt: str = DELTA,
    source_format: str | None = None,
    run_id: str | None = None,
) -> LayerResult:
    """Read bronze, conform, and overwrite silver.

    Silver is rebuilt from bronze each run (full refresh) which is simple, idempotent and
    correct for datasets of moderate size; ``replaceWhere`` or MERGE-based incremental
    variants build on the same :func:`transform_bronze_to_silver` function.
    """
    run_id = run_id or uuid.uuid4().hex
    logger.info("[%s] bronze -> silver starting: %s", run_id, source_path)

    bronze = spark.read.format(source_format or fmt).load(source_path)
    rows_in = bronze.count()
    silver = transform_bronze_to_silver(bronze, config, run_id=run_id)
    rows_out = silver.count()

    write_table(
        silver,
        target_path,
        fmt=fmt,
        mode="overwrite",
        partition_by=config.partition_columns,
        merge_schema=True,
        overwrite_schema=True,
    )
    logger.info("[%s] bronze -> silver complete: %d in, %d out", run_id, rows_in, rows_out)
    return LayerResult(run_id, rows_in, rows_out, target_path)
