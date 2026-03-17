"""
Data Quality Validation Framework
Reusable checks for medallion architecture layers. Run as quality gates
in ETL pipelines before promoting data between layers.
"""

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import StringType
from dataclasses import dataclass, field
from typing import List, Optional
from datetime import datetime


@dataclass
class CheckResult:
    name: str
    passed: bool
    details: str
    checked: int
    failed: int = 0


class DataQualityValidator:

    def __init__(self, df: DataFrame, dataset_name: str):
        self.df = df
        self.name = dataset_name
        self.results: List[CheckResult] = []
        self._count = None

    @property
    def count(self):
        if self._count is None:
            self._count = self.df.count()
        return self._count

    def check_not_null(self, columns: list):
        for col in columns:
            nulls = self.df.filter(F.col(col).isNull()).count()
            self.results.append(CheckResult(
                f"not_null:{col}", nulls == 0,
                f"{nulls}/{self.count} nulls in '{col}'", self.count, nulls
            ))
        return self

    def check_unique(self, columns: list):
        distinct = self.df.select(columns).distinct().count()
        dupes = self.count - distinct
        self.results.append(CheckResult(
            f"unique:{','.join(columns)}", dupes == 0,
            f"{dupes} duplicates across {columns}", self.count, dupes
        ))
        return self

    def check_accepted_values(self, column: str, accepted: list):
        invalid = self.df.filter(~F.col(column).isin(accepted)).count()
        self.results.append(CheckResult(
            f"accepted:{column}", invalid == 0,
            f"{invalid} invalid values in '{column}'", self.count, invalid
        ))
        return self

    def check_row_count(self, min_rows: int, max_rows: Optional[int] = None):
        ok = self.count >= min_rows and (max_rows is None or self.count <= max_rows)
        self.results.append(CheckResult(
            "row_count", ok,
            f"{self.count} rows (expected {min_rows}-{max_rows or 'inf'})", self.count
        ))
        return self

    def check_freshness(self, ts_col: str, max_hours: int = 24):
        latest = self.df.agg(F.max(ts_col)).collect()[0][0]
        if latest:
            age = (datetime.now() - latest).total_seconds() / 3600
            ok = age <= max_hours
            detail = f"Latest: {latest} ({age:.1f}h ago)"
        else:
            ok, detail = False, f"No data in '{ts_col}'"
        self.results.append(CheckResult(f"freshness:{ts_col}", ok, detail, self.count))
        return self

    def check_no_negative(self, columns: list):
        for col in columns:
            neg = self.df.filter(F.col(col) < 0).count()
            self.results.append(CheckResult(
                f"no_negative:{col}", neg == 0,
                f"{neg} negative values in '{col}'", self.count, neg
            ))
        return self

    def validate(self, fail_on_error=True):
        print(f"\n{'='*60}")
        print(f"Data Quality: {self.name} | {self.count} records")
        print(f"{'='*60}\n")

        for r in self.results:
            icon = "PASS" if r.passed else "FAIL"
            color_hint = "+" if r.passed else "X"
            print(f"  [{color_hint}] {r.name}: {icon} - {r.details}")

        passed = sum(1 for r in self.results if r.passed)
        total = len(self.results)
        print(f"\nResult: {passed}/{total} passed")

        if not all(r.passed for r in self.results) and fail_on_error:
            raise ValueError(f"Quality check failed for '{self.name}'")
        return self.results


if __name__ == "__main__":
    from pyspark.sql import SparkSession
    spark = SparkSession.builder.appName("dq").getOrCreate()
    df = spark.read.format("delta").load("abfss://silver@datalake.dfs.core.windows.net/claims/")

    (DataQualityValidator(df, "claims_silver")
     .check_not_null(["claim_id", "policy_number", "claim_date"])
     .check_unique(["claim_id"])
     .check_accepted_values("claim_type", ["motor", "home", "health", "life"])
     .check_row_count(min_rows=1000)
     .check_freshness("_processed_at", max_hours=24)
     .check_no_negative(["claim_amount"])
     .validate(fail_on_error=True))
