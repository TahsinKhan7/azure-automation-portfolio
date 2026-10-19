from __future__ import annotations

import pytest
from pyspark.sql import functions as F

from dataplatform.etl import aggregations as A
from dataplatform.etl.silver_to_gold import GoldConfig, build_gold_datasets, run_silver_to_gold

pytestmark = pytest.mark.spark

GOLD = GoldConfig(
    date_column="claim_date", value_column="claim_amount", group_columns=["business_unit"]
)


def test_gold_config_validation() -> None:
    with pytest.raises(ValueError):
        GoldConfig(date_column="", value_column="x")


def test_daily_summary(claims_df) -> None:
    daily = A.daily_summary(claims_df, "claim_date", ["business_unit"], "claim_amount")
    row = daily.filter(F.col("report_date") == "2025-01-10").first()
    assert row["record_count"] == 2  # C001 appears twice in the un-deduplicated fixture
    assert float(row["total_value"]) == 2450.0


def test_monthly_totals_and_mom_change(claims_df) -> None:
    monthly = A.monthly_totals(claims_df, "claim_date", ["business_unit"], "claim_amount")
    with_mom = A.add_mom_change(monthly, ["business_unit"])
    retail = {
        r["year_month"]: r for r in with_mom.filter(F.col("business_unit") == "retail").collect()
    }
    assert retail["2025-01"]["mom_change_pct"] is None  # first period
    jan, feb = float(retail["2025-01"]["total_value"]), float(retail["2025-02"]["total_value"])
    assert float(retail["2025-02"]["previous_value"]) == jan
    assert float(retail["2025-02"]["mom_change_pct"]) == pytest.approx(
        round((feb - jan) / jan * 100, 2)
    )


def test_mom_change_handles_zero_previous(spark) -> None:
    df = spark.createDataFrame(
        [("2025-01", "a", 0.0), ("2025-02", "a", 10.0)], ["year_month", "g", "total_value"]
    )
    rows = A.add_mom_change(df, ["g"]).orderBy("year_month").collect()
    assert rows[1]["mom_change"] == 10.0 and rows[1]["mom_change_pct"] is None


def test_rolling_average(spark) -> None:
    df = spark.createDataFrame(
        [
            ("2025-01", "a", 10.0),
            ("2025-02", "a", 20.0),
            ("2025-03", "a", 30.0),
            ("2025-04", "a", 40.0),
        ],
        ["year_month", "g", "total_value"],
    )
    rows = A.add_rolling_average(df, ["g"], window_size=3).orderBy("year_month").collect()
    assert [r["rolling_avg_3"] for r in rows] == [10.0, 15.0, 20.0, 30.0]
    with pytest.raises(ValueError):
        A.add_rolling_average(df, ["g"], window_size=0)


def test_kpi_snapshot(claims_df) -> None:
    row = A.kpi_snapshot(claims_df, "claim_date", "claim_amount", ["business_unit"]).first()
    assert row["total_records"] == 7
    assert row["distinct_business_unit"] == 2
    assert str(row["earliest_record"]) == "2025-01-10" and str(row["latest_record"]) == "2025-03-18"


def test_build_gold_datasets_shapes(claims_df) -> None:
    gold = build_gold_datasets(claims_df, GOLD, run_id="r")
    assert set(gold) == {"daily_summary", "monthly_trends", "kpi_snapshot"}
    assert gold["kpi_snapshot"].count() == 1
    assert {"mom_change_pct", "rolling_avg_3", "_aggregated_at", "_run_id"} <= set(
        gold["monthly_trends"].columns
    )


def test_run_silver_to_gold_writes_delta_tables(spark, claims_df, tmp_path) -> None:
    silver = str(tmp_path / "silver")
    gold = str(tmp_path / "gold")
    claims_df.write.format("delta").save(silver)
    counts = run_silver_to_gold(spark, silver, gold, GOLD, fmt="delta")
    assert counts["kpi_snapshot"] == 1
    assert (
        counts["monthly_trends"]
        == spark.read.format("delta").load(f"{gold}/monthly_trends/").count()
    )
    assert (tmp_path / "gold" / "daily_summary" / "_delta_log").is_dir()
