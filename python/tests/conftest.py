"""Shared fixtures: one local Delta-enabled SparkSession per test session plus sample data."""

from __future__ import annotations

import logging
import shutil
import subprocess
import tempfile
from collections.abc import Iterator
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

import pytest
from pyspark.sql import DataFrame, SparkSession

from dataplatform.spark.session import get_spark

logging.getLogger("py4j").setLevel(logging.WARNING)

CONFIG_DIR = Path(__file__).resolve().parents[1] / "config"


def _java_available() -> bool:
    if shutil.which("java") is None:
        return False
    try:
        subprocess.run(["java", "-version"], capture_output=True, check=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return False
    return True


def pytest_collection_modifyitems(config: pytest.Config, items: list[pytest.Item]) -> None:
    """Skip Spark-backed tests when no JVM is available rather than erroring."""
    if _java_available():
        return
    skip = pytest.mark.skip(reason="Java runtime not found; Spark tests skipped")
    for item in items:
        if "spark" in item.fixturenames or item.get_closest_marker("spark"):
            item.add_marker(skip)


@pytest.fixture(scope="session")
def spark() -> Iterator[SparkSession]:
    warehouse = tempfile.mkdtemp(prefix="dataplatform-warehouse-")
    session = get_spark("dataplatform-tests", local=True, warehouse_dir=warehouse)
    yield session
    session.stop()
    shutil.rmtree(warehouse, ignore_errors=True)


@pytest.fixture(scope="session")
def config_dir() -> Path:
    return CONFIG_DIR


# ----------------------------------------------------------------------------- sample data
CUSTOMERS_SCHEMA = (
    "customer_id STRING, full_name STRING, email STRING, postcode STRING, "
    "segment STRING, updated_at TIMESTAMP"
)

CLAIMS_SCHEMA = (
    "claim_id STRING, policy_number STRING, claim_date DATE, claim_type STRING, "
    "claim_amount DECIMAL(18,2), business_unit STRING, status STRING, _ingested_at TIMESTAMP"
)


def _claims_rows() -> list[tuple]:
    t = datetime
    return [
        (
            "C001",
            "POL-000001",
            date(2025, 1, 10),
            "motor",
            Decimal("1200.00"),
            "retail",
            "open",
            t(2025, 1, 11, 8),
        ),
        (
            "C002",
            "POL-000002",
            date(2025, 1, 15),
            "home",
            Decimal("5400.50"),
            "retail",
            "settled",
            t(2025, 1, 16, 8),
        ),
        (
            "C003",
            "POL-000003",
            date(2025, 2, 3),
            "motor",
            Decimal("800.00"),
            "commercial",
            "open",
            t(2025, 2, 4, 8),
        ),
        (
            "C004",
            "POL-000004",
            date(2025, 2, 20),
            "travel",
            Decimal("250.00"),
            "retail",
            "settled",
            t(2025, 2, 21, 8),
        ),
        (
            "C005",
            "POL-000005",
            date(2025, 3, 5),
            "motor",
            Decimal("3100.00"),
            "retail",
            "open",
            t(2025, 3, 6, 8),
        ),
        (
            "C006",
            "POL-000006",
            date(2025, 3, 18),
            "home",
            Decimal("9800.00"),
            "commercial",
            "settled",
            t(2025, 3, 19, 8),
        ),
        # late-arriving correction for C001: should win de-duplication (newer _ingested_at)
        (
            "C001",
            "POL-000001",
            date(2025, 1, 10),
            "motor",
            Decimal("1250.00"),
            "retail",
            "settled",
            t(2025, 1, 12, 8),
        ),
    ]


@pytest.fixture(scope="session")
def claims_df(spark: SparkSession) -> DataFrame:
    """Conformed-looking claims with one duplicate key (C001) and three months of data."""
    return spark.createDataFrame(_claims_rows(), schema=CLAIMS_SCHEMA)


@pytest.fixture(scope="session")
def raw_claims_df(spark: SparkSession) -> DataFrame:
    """Bronze-style claims: messy headers, sentinel nulls and string-typed values."""
    rows = [
        (
            "C001",
            "POL-000001",
            "2025-01-10",
            "motor",
            "1200.00",
            "retail",
            "open",
            "2025-01-11 08:00:00",
        ),
        (
            "C002",
            "POL-000002",
            "2025-01-15",
            "N/A",
            "5400.50",
            " retail ",
            "settled",
            "2025-01-16 08:00:00",
        ),
        ("C003", "POL-000003", "2025-02-03", "motor", "800.00", "", "open", "2025-02-04 08:00:00"),
        (
            "C001",
            "POL-000001",
            "2025-01-10",
            "motor",
            "1250.00",
            "retail",
            "settled",
            "2025-01-12 08:00:00",
        ),
    ]
    return spark.createDataFrame(
        rows,
        [
            "Claim ID",
            "Policy Number",
            "Claim Date",
            "Claim Type",
            "Claim Amount (GBP)",
            "Business Unit",
            "Status",
            "_ingested_at",
        ],
    )


@pytest.fixture(scope="session")
def customers_df(spark: SparkSession) -> DataFrame:
    rows = [
        (
            "CUST-1",
            "Alice Example",
            "alice@example.com",
            "SW1A 1AA",
            "retail",
            datetime(2025, 1, 1),
        ),
        ("CUST-2", "Bob Example", "bob@example.com", "M1 1AE", "commercial", datetime(2025, 1, 1)),
        ("CUST-3", "Chen Example", "chen@example.com", "EH1 1YZ", "broker", datetime(2025, 1, 1)),
    ]
    return spark.createDataFrame(
        rows,
        CUSTOMERS_SCHEMA,
    )


@pytest.fixture
def delta_path(tmp_path: Path) -> str:
    return str(tmp_path / "delta_table")
