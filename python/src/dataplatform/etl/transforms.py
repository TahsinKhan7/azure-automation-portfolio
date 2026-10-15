"""Pure, composable DataFrame transforms.

Every function here takes a DataFrame (plus plain-Python parameters) and returns a new
DataFrame. None of them read, write, or touch the SparkSession, which keeps them trivially
unit testable and reusable across datasets and layers.
"""

from __future__ import annotations

import re
from collections.abc import Iterable, Mapping, Sequence

from pyspark.sql import Column, DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import StringType
from pyspark.sql.window import Window

DEFAULT_NULL_TOKENS: tuple[str, ...] = ("", "null", "none", "n/a", "na", "nan", "-")
"""Case-insensitive sentinel strings that source systems commonly use to mean "no value"."""

_NON_ALNUM = re.compile(r"[^0-9a-zA-Z]+")


def normalise_column_name(name: str) -> str:
    """Convert an arbitrary header into a ``snake_case`` identifier.

    ``" Claim Amount (GBP) "`` becomes ``claim_amount_gbp``; names beginning with a digit are
    prefixed with an underscore so they remain valid unquoted identifiers.
    """
    stripped = name.strip()
    cleaned = _NON_ALNUM.sub("_", stripped).strip("_").lower()
    cleaned = re.sub(r"_+", "_", cleaned)
    if cleaned and (cleaned[0].isdigit() or stripped.startswith("_")):
        # keep the leading underscore convention used for metadata columns (``_ingested_at``)
        cleaned = f"_{cleaned}"
    return cleaned or "_unnamed"


def clean_column_names(df: DataFrame) -> DataFrame:
    """Rename every column to its normalised ``snake_case`` form.

    Raises:
        ValueError: if two source columns normalise to the same name, since silently
            dropping one would corrupt the dataset.
    """
    mapping = {col: normalise_column_name(col) for col in df.columns}
    seen: dict[str, str] = {}
    for original, cleaned in mapping.items():
        if cleaned in seen:
            raise ValueError(
                f"Columns '{seen[cleaned]}' and '{original}' both normalise to '{cleaned}'"
            )
        seen[cleaned] = original
    return df.select([F.col(f"`{col}`").alias(mapping[col]) for col in df.columns])


def rename_columns(df: DataFrame, mapping: Mapping[str, str]) -> DataFrame:
    """Rename columns according to ``mapping`` (missing source columns are ignored)."""
    return df.select([F.col(f"`{col}`").alias(mapping.get(col, col)) for col in df.columns])


def trim_strings(df: DataFrame, columns: Iterable[str] | None = None) -> DataFrame:
    """Trim leading and trailing whitespace from string columns."""
    targets = list(columns) if columns is not None else _string_columns(df)
    return df.withColumns({col: F.trim(F.col(col)) for col in targets})


def standardise_nulls(
    df: DataFrame,
    columns: Iterable[str] | None = None,
    null_tokens: Sequence[str] = DEFAULT_NULL_TOKENS,
    default: str | None = None,
) -> DataFrame:
    """Turn sentinel strings into real nulls, optionally filling them with ``default``.

    Comparison is case-insensitive and ignores surrounding whitespace, so ``" NULL "``,
    ``"n/a"`` and ``""`` all become null. When ``default`` is given the resulting nulls are
    replaced with it (for example ``"UNKNOWN"`` for categorical columns).
    """
    targets = list(columns) if columns is not None else _string_columns(df)
    tokens = [token.lower() for token in null_tokens]
    expressions: dict[str, Column] = {}
    for col in targets:
        trimmed = F.trim(F.col(col))
        as_null = F.when(F.lower(trimmed).isin(tokens), F.lit(None)).otherwise(trimmed)
        expressions[col] = F.coalesce(as_null, F.lit(default)) if default is not None else as_null
    return df.withColumns(expressions)


def deduplicate_latest(
    df: DataFrame,
    key_columns: Sequence[str],
    order_column: str | None = None,
    descending: bool = True,
) -> DataFrame:
    """Keep one row per key.

    When ``order_column`` is present the row with the greatest (or smallest, if
    ``descending=False``) value wins, which is the usual "latest record" semantics for
    change feeds. Otherwise an arbitrary row per key is kept via ``dropDuplicates``.
    """
    if not key_columns:
        raise ValueError("key_columns must not be empty")
    if order_column is None or order_column not in df.columns:
        return df.dropDuplicates(list(key_columns))
    ordering = F.col(order_column).desc_nulls_last() if descending else F.col(order_column).asc()
    window = Window.partitionBy(*key_columns).orderBy(ordering)
    return (
        df.withColumn("_row_number", F.row_number().over(window))
        .filter(F.col("_row_number") == 1)
        .drop("_row_number")
    )


def cast_schema(
    df: DataFrame,
    spec: Mapping[str, str],
    strict: bool = False,
    drop_unlisted: bool = False,
) -> DataFrame:
    """Cast columns to the Spark SQL types named in ``spec`` (``{"amount": "decimal(18,2)"}``).

    Args:
        spec: Mapping of column name to Spark type string.
        strict: Raise if a column from ``spec`` is missing from the DataFrame; otherwise the
            missing column is added as a typed null so downstream schemas stay stable.
        drop_unlisted: Keep only the columns named in ``spec`` (in that order).
    """
    missing = [col for col in spec if col not in df.columns]
    if strict and missing:
        raise ValueError(f"Columns missing from DataFrame: {missing}")
    out = df
    for col, dtype in spec.items():
        source = F.col(col) if col in out.columns else F.lit(None)
        out = out.withColumn(col, source.cast(dtype))
    if drop_unlisted:
        out = out.select(*spec.keys())
    return out


def add_audit_columns(
    df: DataFrame,
    etl_version: str,
    run_id: str | None = None,
    processed_at_column: str = "_processed_at",
) -> DataFrame:
    """Append processing metadata (``_processed_at``, ``_etl_version``, ``_run_id``)."""
    return df.withColumns(
        {
            processed_at_column: F.current_timestamp(),
            "_etl_version": F.lit(etl_version),
            "_run_id": F.lit(run_id),
        }
    )


def derive_period_columns(
    df: DataFrame,
    date_column: str,
    prefix: str = "",
    include_quarter: bool = False,
) -> DataFrame:
    """Add ``year``, ``month`` and ``year_month`` (and optionally ``quarter``) columns.

    These are the usual partitioning and reporting keys for date-driven facts.
    """
    source = F.col(date_column)
    columns = {
        f"{prefix}year": F.year(source),
        f"{prefix}month": F.month(source),
        f"{prefix}year_month": F.date_format(source, "yyyy-MM"),
    }
    if include_quarter:
        columns[f"{prefix}quarter"] = F.quarter(source)
    return df.withColumns(columns)


def select_columns(df: DataFrame, columns: Sequence[str], allow_missing: bool = False) -> DataFrame:
    """Project ``columns`` in order, failing loudly on typos unless ``allow_missing``."""
    missing = [col for col in columns if col not in df.columns]
    if missing and not allow_missing:
        raise ValueError(f"Columns missing from DataFrame: {missing}")
    return df.select([col for col in columns if col in df.columns])


def _string_columns(df: DataFrame) -> list[str]:
    return [f.name for f in df.schema.fields if isinstance(f.dataType, StringType)]
