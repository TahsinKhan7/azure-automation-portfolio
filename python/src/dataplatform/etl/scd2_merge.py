"""Slowly Changing Dimension Type 2 on Delta Lake.

Change detection uses a hash of the tracked attributes (``_hash_diff``) so that any number of
columns can be compared with a single equality test. The merge follows the standard staging
pattern: every incoming row is submitted with its business key (new keys insert, changed
keys expire their current row, unchanged keys are a no-op) and each *changed* key is
submitted a second time with a null merge key so its new version is inserted. The whole
operation is a single atomic Delta ``MERGE``.

Change detection is a pure DataFrame function so the logic can be tested without Delta; the
merge itself is exercised against a local Delta table in the test suite.
"""

from __future__ import annotations

import logging
from collections.abc import Sequence
from dataclasses import dataclass

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F

logger = logging.getLogger(__name__)

NULL_SENTINEL = "␟"
"""Stands in for NULL before hashing; a control picture that never appears in real data."""

FIELD_SEPARATOR = "␞"
"""Separates fields before hashing so column boundaries cannot be confused."""


@dataclass(frozen=True)
class Scd2Config:
    """Columns that define identity, change and validity for a dimension."""

    key_columns: Sequence[str]
    tracked_columns: Sequence[str]
    effective_from_column: str = "effective_from"
    effective_to_column: str = "effective_to"
    current_flag_column: str = "is_current"
    hash_column: str = "_hash_diff"
    source_effective_from_column: str | None = None
    """Optional source column (e.g. ``updated_at``) used as the version start timestamp."""

    def __post_init__(self) -> None:
        if not self.key_columns:
            raise ValueError("key_columns must not be empty")
        if not self.tracked_columns:
            raise ValueError("tracked_columns must not be empty")
        overlap = set(self.key_columns) & set(self.tracked_columns)
        if overlap:
            raise ValueError(f"Columns cannot be both key and tracked: {sorted(overlap)}")

    @property
    def dimension_columns(self) -> list[str]:
        return [
            *self.key_columns,
            *self.tracked_columns,
            self.hash_column,
            self.effective_from_column,
            self.effective_to_column,
            self.current_flag_column,
        ]


@dataclass(frozen=True)
class Scd2Result:
    """Row counts for one SCD2 apply."""

    inserted: int
    expired: int
    unchanged: int
    initial_load: bool = False


def add_hash_diff(
    df: DataFrame, columns: Sequence[str], hash_column: str = "_hash_diff"
) -> DataFrame:
    """Add a SHA-256 of the tracked columns.

    Nulls are replaced with a sentinel before hashing so ``NULL`` and ``""`` hash differently,
    and fields are joined with a separator so ``("ab", "c")`` and ``("a", "bc")`` differ.
    """
    parts = [F.coalesce(F.col(col).cast("string"), F.lit(NULL_SENTINEL)) for col in columns]
    return df.withColumn(hash_column, F.sha2(F.concat_ws(FIELD_SEPARATOR, *parts), 256))


def prepare_source(
    df: DataFrame, config: Scd2Config, effective_from: str | None = None
) -> DataFrame:
    """Project the source to key + tracked columns, add the hash and the version start."""
    if config.source_effective_from_column:
        start = F.col(config.source_effective_from_column).cast("timestamp")
    elif effective_from:
        start = F.lit(effective_from).cast("timestamp")
    else:
        start = F.current_timestamp()

    columns = [*config.key_columns, *config.tracked_columns]
    extra = config.source_effective_from_column
    if extra and extra not in columns:
        columns.append(extra)
    out = add_hash_diff(df.select(*columns), config.tracked_columns, config.hash_column)
    return out.withColumn(config.effective_from_column, start)


def initial_dimension(
    df: DataFrame, config: Scd2Config, effective_from: str | None = None
) -> DataFrame:
    """Build the first version of a dimension: every row current and open-ended."""
    prepared = prepare_source(df, config, effective_from)
    return prepared.select(
        *config.key_columns,
        *config.tracked_columns,
        config.hash_column,
        config.effective_from_column,
        F.lit(None).cast("timestamp").alias(config.effective_to_column),
        F.lit(True).alias(config.current_flag_column),
    )


def detect_changes(current: DataFrame, incoming: DataFrame, config: Scd2Config) -> DataFrame:
    """Classify each incoming row as ``insert``, ``update`` or ``unchanged``.

    ``current`` is the existing dimension (only current rows are considered); ``incoming`` is
    the prepared source (see :func:`prepare_source`). The result carries the incoming columns
    plus ``_change_type``.
    """
    keys = list(config.key_columns)
    active = current.filter(F.col(config.current_flag_column)).select(
        *keys, F.col(config.hash_column).alias("_current_hash")
    )
    joined = incoming.join(active, on=keys, how="left")
    change_type = (
        F.when(F.col("_current_hash").isNull(), F.lit("insert"))
        .when(F.col("_current_hash") != F.col(config.hash_column), F.lit("update"))
        .otherwise(F.lit("unchanged"))
    )
    return joined.withColumn("_change_type", change_type).drop("_current_hash")


def build_staged_updates(classified: DataFrame, config: Scd2Config) -> DataFrame:
    """Stage rows for the MERGE (see module docstring for why changed keys appear twice)."""
    merge_key = F.concat_ws(FIELD_SEPARATOR, *[F.col(c).cast("string") for c in config.key_columns])
    rows = classified.drop("_change_type")
    keyed = rows.withColumn("_merge_key", merge_key)
    new_versions = (
        classified.filter(F.col("_change_type") == "update")
        .drop("_change_type")
        .withColumn("_merge_key", F.lit(None).cast("string"))
    )
    return keyed.unionByName(new_versions)


def apply_scd2(
    spark: SparkSession,
    target_path: str,
    source: DataFrame,
    config: Scd2Config,
    effective_from: str | None = None,
) -> Scd2Result:
    """Merge ``source`` into the Delta dimension at ``target_path`` with SCD2 semantics.

    New keys are inserted; keys whose tracked attributes changed have their current row
    expired (``effective_to`` set, ``is_current`` false) and a new current row inserted.
    Unchanged keys, and keys absent from the source, are untouched.
    """
    from delta.tables import DeltaTable

    if not DeltaTable.isDeltaTable(spark, target_path):
        dimension = initial_dimension(source, config, effective_from)
        dimension.write.format("delta").mode("overwrite").save(target_path)
        inserted = spark.read.format("delta").load(target_path).count()
        logger.info("SCD2 initial load -> %s (%d rows)", target_path, inserted)
        return Scd2Result(inserted=inserted, expired=0, unchanged=0, initial_load=True)

    target = DeltaTable.forPath(spark, target_path)
    incoming = prepare_source(source, config, effective_from)
    classified = detect_changes(target.toDF(), incoming, config).cache()
    counts = {
        row["_change_type"]: row["count"]
        for row in classified.groupBy("_change_type").count().collect()
    }
    inserts, updates, unchanged = (
        counts.get("insert", 0),
        counts.get("update", 0),
        counts.get("unchanged", 0),
    )
    if not (inserts or updates):
        classified.unpersist()
        logger.info("SCD2: no changes for %s", target_path)
        return Scd2Result(inserted=0, expired=0, unchanged=unchanged)

    staged = build_staged_updates(classified, config)
    target_key = ", ".join(f"CAST(target.{c} AS STRING)" for c in config.key_columns)
    condition = (
        f"concat_ws('{FIELD_SEPARATOR}', {target_key}) = staged._merge_key "
        f"AND target.{config.current_flag_column} = true"
    )
    insert_values = {
        **{c: f"staged.{c}" for c in (*config.key_columns, *config.tracked_columns)},
        config.hash_column: f"staged.{config.hash_column}",
        config.effective_from_column: f"staged.{config.effective_from_column}",
        config.effective_to_column: "CAST(NULL AS TIMESTAMP)",
        config.current_flag_column: "true",
    }
    (
        target.alias("target")
        .merge(staged.alias("staged"), condition)
        .whenMatchedUpdate(
            condition=f"target.{config.hash_column} <> staged.{config.hash_column}",
            set={
                config.current_flag_column: "false",
                config.effective_to_column: f"staged.{config.effective_from_column}",
            },
        )
        .whenNotMatchedInsert(values=insert_values)
        .execute()
    )
    classified.unpersist()
    logger.info(
        "SCD2 merge -> %s: %d inserted, %d expired, %d unchanged",
        target_path,
        inserts + updates,
        updates,
        unchanged,
    )
    return Scd2Result(inserted=inserts + updates, expired=updates, unchanged=unchanged)
