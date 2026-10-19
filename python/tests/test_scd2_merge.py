from __future__ import annotations

from datetime import datetime

import pytest
from pyspark.sql import functions as F

from dataplatform.etl.scd2_merge import (
    Scd2Config,
    add_hash_diff,
    apply_scd2,
    build_staged_updates,
    detect_changes,
    initial_dimension,
    prepare_source,
)

pytestmark = pytest.mark.spark

CONFIG = Scd2Config(
    key_columns=["customer_id"], tracked_columns=["full_name", "email", "postcode", "segment"]
)
SCHEMA = (
    "customer_id STRING, full_name STRING, email STRING, postcode STRING, "
    "segment STRING, updated_at TIMESTAMP"
)


def test_config_validation() -> None:
    with pytest.raises(ValueError):
        Scd2Config(key_columns=[], tracked_columns=["a"])
    with pytest.raises(ValueError):
        Scd2Config(key_columns=["a"], tracked_columns=["a", "b"])
    assert CONFIG.dimension_columns[-1] == "is_current"


def test_hash_diff_distinguishes_null_empty_and_boundaries(spark) -> None:
    df = spark.createDataFrame([("ab", "c"), ("a", "bc"), (None, ""), ("", None)], ["x", "y"])
    hashes = [r["_hash_diff"] for r in add_hash_diff(df, ["x", "y"]).collect()]
    assert len(set(hashes)) == 4
    assert all(len(h) == 64 for h in hashes)


def test_hash_diff_is_deterministic(customers_df) -> None:
    a = add_hash_diff(customers_df, CONFIG.tracked_columns).select("_hash_diff").collect()
    b = add_hash_diff(customers_df, CONFIG.tracked_columns).select("_hash_diff").collect()
    assert a == b


def test_detect_changes_classifies_rows(spark, customers_df) -> None:
    current = initial_dimension(customers_df, CONFIG, effective_from="2025-01-01 00:00:00")
    incoming_rows = [
        (
            "CUST-1",
            "Alice Example",
            "alice@example.com",
            "SW1A 1AA",
            "retail",
            datetime(2025, 2, 1),
        ),  # unchanged
        (
            "CUST-2",
            "Bob Example",
            "bob.new@example.com",
            "M1 1AE",
            "commercial",
            datetime(2025, 2, 1),
        ),  # update
        (
            "CUST-9",
            "New Person",
            "new@example.com",
            "B1 1AA",
            "retail",
            datetime(2025, 2, 1),
        ),  # insert
    ]
    incoming = prepare_source(
        spark.createDataFrame(incoming_rows, SCHEMA), CONFIG, "2025-02-01 00:00:00"
    )
    classified = {
        r["customer_id"]: r["_change_type"]
        for r in detect_changes(current, incoming, CONFIG).collect()
    }
    assert classified == {"CUST-1": "unchanged", "CUST-2": "update", "CUST-9": "insert"}


def test_staged_updates_duplicate_only_changed_keys(spark, customers_df) -> None:
    current = initial_dimension(customers_df, CONFIG, effective_from="2025-01-01 00:00:00")
    incoming_rows = [
        (
            "CUST-2",
            "Bob Example",
            "bob.new@example.com",
            "M1 1AE",
            "commercial",
            datetime(2025, 2, 1),
        ),
        ("CUST-9", "New Person", "new@example.com", "B1 1AA", "retail", datetime(2025, 2, 1)),
    ]
    incoming = prepare_source(
        spark.createDataFrame(incoming_rows, SCHEMA), CONFIG, "2025-02-01 00:00:00"
    )
    staged = build_staged_updates(detect_changes(current, incoming, CONFIG), CONFIG)
    rows = (
        staged.groupBy("customer_id")
        .agg(
            F.count("*").alias("n"), F.sum(F.col("_merge_key").isNull().cast("int")).alias("nulls")
        )
        .collect()
    )
    by_key = {r["customer_id"]: (r["n"], r["nulls"]) for r in rows}
    assert by_key == {"CUST-2": (2, 1), "CUST-9": (1, 0)}


def test_initial_load_then_merge(spark, customers_df, delta_path) -> None:
    first = apply_scd2(
        spark, delta_path, customers_df, CONFIG, effective_from="2025-01-01 00:00:00"
    )
    assert first.initial_load and first.inserted == 3

    incoming_rows = [
        (
            "CUST-1",
            "Alice Example",
            "alice@example.com",
            "SW1A 1AA",
            "retail",
            datetime(2025, 2, 1),
        ),
        (
            "CUST-2",
            "Bob Example",
            "bob.new@example.com",
            "M1 1AE",
            "commercial",
            datetime(2025, 2, 1),
        ),
        ("CUST-9", "New Person", "new@example.com", "B1 1AA", "retail", datetime(2025, 2, 1)),
    ]
    second = apply_scd2(
        spark,
        delta_path,
        spark.createDataFrame(incoming_rows, SCHEMA),
        CONFIG,
        effective_from="2025-02-01 00:00:00",
    )
    assert (second.inserted, second.expired, second.unchanged) == (2, 1, 1)

    dim = spark.read.format("delta").load(delta_path)
    assert dim.count() == 5  # 3 original + 1 new version of CUST-2 + 1 new key
    assert dim.filter("is_current").count() == 4
    bob = dim.filter("customer_id = 'CUST-2'").orderBy("effective_from").collect()
    assert [r["is_current"] for r in bob] == [False, True]
    assert bob[0]["effective_to"] == datetime(2025, 2, 1) and bob[1]["effective_to"] is None
    assert bob[1]["email"] == "bob.new@example.com"
    assert dim.filter("customer_id = 'CUST-9'").count() == 1  # new keys are inserted exactly once


def test_merge_with_no_changes_is_noop(spark, customers_df, delta_path) -> None:
    apply_scd2(spark, delta_path, customers_df, CONFIG, effective_from="2025-01-01 00:00:00")
    before = spark.read.format("delta").load(delta_path).collect()
    result = apply_scd2(
        spark, delta_path, customers_df, CONFIG, effective_from="2025-03-01 00:00:00"
    )
    assert (result.inserted, result.expired, result.unchanged) == (0, 0, 3)
    assert spark.read.format("delta").load(delta_path).collect() == before


def test_effective_from_taken_from_source_column(spark, customers_df, delta_path) -> None:
    config = Scd2Config(
        key_columns=["customer_id"],
        tracked_columns=["full_name", "email", "postcode", "segment"],
        source_effective_from_column="updated_at",
    )
    apply_scd2(spark, delta_path, customers_df, config)
    dim = spark.read.format("delta").load(delta_path)
    assert {r["effective_from"] for r in dim.collect()} == {datetime(2025, 1, 1)}
