"""dataplatform: medallion lakehouse toolkit for Azure Databricks.

The package is organised by concern:

* ``config``     - typed, per-environment settings loaded from YAML and environment variables.
* ``spark``      - Delta-enabled SparkSession factory (local mode for tests).
* ``etl``        - pure DataFrame transforms plus thin orchestration for each medallion hop.
* ``quality``    - data quality validator, YAML expectation suites and quarantine helpers.
* ``databricks`` - Databricks / Azure platform clients (SDK first, REST fallback).
* ``cli``        - argparse entry points wired up in ``pyproject.toml``.
"""

__version__ = "1.0.0"
__all__ = ["__version__"]
