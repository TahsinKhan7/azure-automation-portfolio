"""Landing -> bronze ingestion.

Reads raw files with an explicit schema, separates malformed records into a quarantine
location, stamps ingestion metadata and appends to the bronze table. On Databricks the
same logic can run through Auto Loader (``cloudFiles``) for incremental, exactly-once file
discovery; locally and in tests a plain batch reader is used.
"""

from __future__ import annotations

import logging
import uuid
from collections.abc import Mapping
from dataclasses import dataclass, field

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import StringType, StructField, StructType

from dataplatform.etl.writers import DELTA, write_table
from dataplatform.spark.session import schema_from_ddl

logger = logging.getLogger(__name__)

CORRUPT_RECORD_COLUMN = "_corrupt_record"
SOURCE_FILE_COLUMN = "_source_file"
SUPPORTED_FORMATS = ("csv", "json", "parquet")


@dataclass(frozen=True)
class IngestConfig:
    """Parameters for ingesting one dataset from the landing zone."""

    dataset: str
    source_format: str
    schema: StructType
    options: Mapping[str, str] = field(default_factory=dict)
    partition_columns: tuple[str, ...] = ()
    use_autoloader: bool = False
    checkpoint_path: str | None = None

    def __post_init__(self) -> None:
        if self.source_format not in SUPPORTED_FORMATS:
            raise ValueError(
                f"Unsupported source_format '{self.source_format}'; expected {SUPPORTED_FORMATS}"
            )
        if self.use_autoloader and not self.checkpoint_path:
            raise ValueError("checkpoint_path is required when use_autoloader=True")


@dataclass(frozen=True)
class IngestResult:
    """Row counts produced by one ingestion run."""

    dataset: str
    run_id: str
    rows_ingested: int
    rows_quarantined: int

    @property
    def rows_read(self) -> int:
        return self.rows_ingested + self.rows_quarantined


def ingest_config_from_ddl(
    spark: SparkSession,
    dataset: str,
    source_format: str,
    schema_ddl: str,
    options: Mapping[str, str] | None = None,
    partition_columns: tuple[str, ...] | list[str] = (),
    **kwargs: object,
) -> IngestConfig:
    """Build an :class:`IngestConfig` from a DDL schema string (as stored in ``datasets.yml``)."""
    return IngestConfig(
        dataset=dataset,
        source_format=source_format,
        schema=schema_from_ddl(spark, schema_ddl),
        options=dict(options or {}),
        partition_columns=tuple(partition_columns),
        **kwargs,  # type: ignore[arg-type]
    )


def with_corrupt_record_column(schema: StructType) -> StructType:
    """Return ``schema`` plus the ``_corrupt_record`` column used by PERMISSIVE parsing."""
    if CORRUPT_RECORD_COLUMN in schema.fieldNames():
        return schema
    return StructType([*schema.fields, StructField(CORRUPT_RECORD_COLUMN, StringType(), True)])


def read_landing(spark: SparkSession, path: str, config: IngestConfig) -> DataFrame:
    """Read raw files with an explicit schema.

    CSV and JSON are parsed in PERMISSIVE mode so that malformed rows land in
    ``_corrupt_record`` instead of failing the whole job. Parquet carries its own schema and
    cannot produce partially-parsed rows, so it is read as-is.
    """
    if config.use_autoloader:
        return _read_autoloader(spark, path, config)

    reader = spark.read.format(config.source_format).options(**config.options)
    if config.source_format == "parquet":
        logger.info("Reading parquet from %s", path)
        return _with_source_file(reader.schema(config.schema).load(path))

    schema = with_corrupt_record_column(config.schema)
    logger.info("Reading %s from %s (PERMISSIVE)", config.source_format, path)
    df = (
        reader.option("mode", "PERMISSIVE")
        .option("columnNameOfCorruptRecord", CORRUPT_RECORD_COLUMN)
        .schema(schema)
        .load(path)
    )
    # Spark refuses to filter solely on the corrupt-record column of a lazily parsed file
    # source, so materialise the parse once before the good/bad split. The file name must be
    # captured first: it is not available once the plan reads from the cache.
    return _with_source_file(df).cache()


def _with_source_file(df: DataFrame) -> DataFrame:
    return df.withColumn(SOURCE_FILE_COLUMN, F.input_file_name())


def _read_autoloader(spark: SparkSession, path: str, config: IngestConfig) -> DataFrame:
    """Databricks Auto Loader reader (streaming source consumed with ``availableNow``)."""
    schema = (
        config.schema
        if config.source_format == "parquet"
        else with_corrupt_record_column(config.schema)
    )
    logger.info("Reading %s via Auto Loader from %s", config.source_format, path)
    return (
        spark.readStream.format("cloudFiles")
        .option("cloudFiles.format", config.source_format)
        .option("cloudFiles.schemaLocation", config.checkpoint_path)
        .option("cloudFiles.useNotifications", "false")
        .option("mode", "PERMISSIVE")
        .option("columnNameOfCorruptRecord", CORRUPT_RECORD_COLUMN)
        .options(**config.options)
        .schema(schema)
        .load(path)
        .withColumn(SOURCE_FILE_COLUMN, F.col("_metadata.file_path"))
    )


def split_bad_records(df: DataFrame) -> tuple[DataFrame, DataFrame]:
    """Split rows into (well-formed, malformed) based on ``_corrupt_record``.

    The well-formed side has the corrupt-record column removed. When the column is absent
    (parquet sources) every row is well-formed and the malformed side is empty.
    """
    if CORRUPT_RECORD_COLUMN not in df.columns:
        return df, df.limit(0).withColumn(CORRUPT_RECORD_COLUMN, F.lit(None).cast("string"))
    good = df.filter(F.col(CORRUPT_RECORD_COLUMN).isNull()).drop(CORRUPT_RECORD_COLUMN)
    bad = df.filter(F.col(CORRUPT_RECORD_COLUMN).isNotNull())
    return good, bad


def add_ingest_metadata(df: DataFrame, run_id: str, dataset: str) -> DataFrame:
    """Stamp ``_ingested_at``, ``_source_file``, ``_ingest_run_id`` and ``_dataset``."""
    columns = {
        "_ingested_at": F.current_timestamp(),
        "_ingest_run_id": F.lit(run_id),
        "_dataset": F.lit(dataset),
    }
    if SOURCE_FILE_COLUMN not in df.columns:
        columns[SOURCE_FILE_COLUMN] = F.input_file_name()
    return df.withColumns(columns)


def run_landing_to_bronze(
    spark: SparkSession,
    source_path: str,
    target_path: str,
    quarantine_path: str,
    config: IngestConfig,
    fmt: str = DELTA,
    run_id: str | None = None,
) -> IngestResult:
    """Ingest one dataset from landing to bronze.

    Well-formed rows are appended to ``target_path``; malformed rows (with their raw text in
    ``_corrupt_record``) are appended to ``quarantine_path`` for triage. Both carry the same
    ingestion metadata so a run can be traced end to end.
    """
    run_id = run_id or uuid.uuid4().hex
    logger.info("[%s] landing -> bronze for '%s' starting", run_id, config.dataset)

    raw = read_landing(spark, source_path, config)
    if config.use_autoloader:
        return _run_autoloader(raw, target_path, quarantine_path, config, fmt, run_id)

    good, bad = split_bad_records(raw)
    good = add_ingest_metadata(good, run_id, config.dataset)
    bad = add_ingest_metadata(bad, run_id, config.dataset)

    rows_ingested = good.count()
    rows_quarantined = bad.count()

    write_table(good, target_path, fmt=fmt, mode="append", partition_by=config.partition_columns)
    if rows_quarantined:
        write_table(bad, quarantine_path, fmt=fmt, mode="append")
        logger.warning(
            "[%s] %d malformed rows quarantined -> %s", run_id, rows_quarantined, quarantine_path
        )
    raw.unpersist()

    result = IngestResult(config.dataset, run_id, rows_ingested, rows_quarantined)
    logger.info(
        "[%s] landing -> bronze complete: %d ingested, %d quarantined",
        run_id,
        rows_ingested,
        rows_quarantined,
    )
    return result


def _run_autoloader(
    stream: DataFrame,
    target_path: str,
    quarantine_path: str,
    config: IngestConfig,
    fmt: str,
    run_id: str,
) -> IngestResult:
    """Drain an Auto Loader stream once (``availableNow``) using ``foreachBatch``."""
    counts = {"good": 0, "bad": 0}

    def _write_batch(batch: DataFrame, batch_id: int) -> None:
        good, bad = split_bad_records(batch)
        good = add_ingest_metadata(good, run_id, config.dataset)
        bad = add_ingest_metadata(bad, run_id, config.dataset)
        counts["good"] += good.count()
        counts["bad"] += bad.count()
        write_table(
            good, target_path, fmt=fmt, mode="append", partition_by=config.partition_columns
        )
        if counts["bad"]:
            write_table(bad, quarantine_path, fmt=fmt, mode="append")
        logger.info("[%s] batch %d written", run_id, batch_id)

    query = (
        stream.writeStream.foreachBatch(_write_batch)
        .option("checkpointLocation", f"{config.checkpoint_path.rstrip('/')}/bronze")
        .trigger(availableNow=True)
        .start()
    )
    query.awaitTermination()
    return IngestResult(config.dataset, run_id, counts["good"], counts["bad"])
