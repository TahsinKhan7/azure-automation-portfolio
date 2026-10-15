# dataplatform - Medallion Lakehouse Toolkit (PySpark, Delta Lake, Databricks)

A pip-installable Python package that implements a landing -> bronze -> silver -> gold
lakehouse on Azure Databricks, with the pieces a hiring manager would expect to see in a
production data platform:

| Capability | Where |
|------------|-------|
| Schema-enforced ingestion with bad-record quarantine, Auto Loader option | `etl/landing_to_bronze.py` |
| Pure, unit-tested DataFrame transforms (naming, nulls, typing, dedup, audit, periods) | `etl/transforms.py` |
| Delta writes with schema evolution, partitioning and `replaceWhere` | `etl/writers.py` |
| Gold KPIs: daily summaries, month-on-month change, rolling averages (window functions) | `etl/aggregations.py` |
| SCD Type 2 dimension with hash-diff change detection and a single atomic Delta `MERGE` | `etl/scd2_merge.py` |
| Data quality gate: fluent validator, YAML expectation suites, row-level quarantine | `quality/` |
| Typed per-environment configuration (dev / ite / iqe / preprod / prod) | `config/`, `config/*.yml` |
| Databricks platform clients: jobs deploy (SDK), clusters, Unity Catalog, Delta maintenance, PAT rotation to Key Vault, ADF monitoring | `databricks/` |
| CLI entry points for ETL, DQ, job deployment and maintenance | `cli.py` |
| Databricks notebooks that are thin wrappers over the package | `notebooks/` |
| 100+ tests on a local Delta-enabled SparkSession, no cloud required | `tests/` |

Nothing here depends on a Databricks workspace to run: the test suite spins up a local
Spark 3.5 session with Delta Lake 3.2 and exercises every layer end to end on temporary
directories.

## Architecture

```mermaid
flowchart LR
    subgraph Sources
        S1[(Azure SQL)]
        S2[CSV / JSON drops]
        S3[Parquet extracts]
    end

    subgraph ADLS Gen2
        L[landing]
        B[(bronze<br/>Delta, append-only<br/>+ _ingested_at, _source_file)]
        Q[(quarantine<br/>malformed + DQ-failed rows)]
        SV[(silver<br/>Delta, conformed<br/>1 row per key, typed, partitioned)]
        G[(gold<br/>daily_summary, monthly_trends,<br/>kpi_snapshot, dim_customer SCD2)]
    end

    S1 & S2 & S3 -->|ADF copy / Auto Loader| L
    L -->|01 landing_to_bronze<br/>explicit schema, PERMISSIVE| B
    L -.->|_corrupt_record| Q
    B -->|02 bronze_to_silver<br/>pure transforms| SV
    SV -->|04 DQ gate<br/>YAML expectations| DQ{pass?}
    DQ -->|yes| G
    DQ -->|no: DataQualityError| STOP[job fails,<br/>gold untouched]
    SV -.->|row-level rules| Q
    SV -->|05 SCD2 MERGE| G
    G -->|06 OPTIMIZE / VACUUM| G
    G --> BI[Power BI / Databricks SQL]
    UC[Unity Catalog<br/>dataplatform_env.bronze|silver|gold] --- B & SV & G
```

Every arrow in the diagram is a function in this package with a test behind it, and every
notebook is a 30-line wrapper that reads widgets, loads settings and calls that function.

## Quick start

```bash
cd python
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"            # pulls pyspark, delta-spark, databricks-sdk, azure-* and dev tools

# Java 11/17/21 is required for local Spark. Delta JARs are fetched once by delta-spark.
java -version

pytest -q                          # ~100 tests, about 1-2 minutes on a laptop
ruff check . && ruff format --check .
```

Run a layer locally against parquet or Delta on disk (no workspace needed):

```bash
dataplatform etl run --layer bronze-to-silver --env dev --dataset claims \
    --source /tmp/bronze/claims --target /tmp/silver/claims --format delta --local

dataplatform dq run --env dev --dataset claims --source /tmp/silver/claims --local

dataplatform jobs deploy --env dev --file config/jobs/medallion_pipeline.yml --dry-run

dataplatform maintenance run --env dev --table dataplatform_dev.silver.claims \
    --zorder-by claim_date,policy_number --dry-run --local
```

Without `--source/--target` the CLI resolves `abfss://` paths from `config/<env>.yml`, and
without `--local` it attaches to the existing Databricks session. Non-secret settings can be
overridden per run with `DATAPLATFORM_STORAGE_ACCOUNT`, `DATAPLATFORM_CATALOG`,
`DATAPLATFORM_WORKSPACE_HOST`, `DATAPLATFORM_KEY_VAULT_NAME` and `DATAPLATFORM_ENV`.

## Folder structure

| Path | Contents |
|------|----------|
| `pyproject.toml` | Package metadata, dependencies, `ruff` and `pytest` configuration, `dataplatform` console script |
| `config/dev.yml` ... `config/prod.yml` | Storage account, catalog, containers and job sizing per environment |
| `config/datasets.yml` | Per-dataset ingestion schema, keys, partitioning, casts and quality suite |
| `config/quality/*.yml` | YAML expectation suites run by the DQ gate |
| `config/jobs/*.yml` | Jobs 2.1 definitions with `{placeholders}` rendered from settings |
| `src/dataplatform/config/` | `Settings`, `DatasetConfig`, `load_settings()` (YAML + env var overrides) |
| `src/dataplatform/spark/` | `get_spark()` Delta-enabled session factory, `schema_from_ddl()` |
| `src/dataplatform/etl/` | `transforms`, `aggregations`, `writers`, `landing_to_bronze`, `bronze_to_silver`, `silver_to_gold`, `scd2_merge` |
| `src/dataplatform/quality/` | `DataQualityValidator`, `ExpectationSuite` runner, `split_quarantine` |
| `src/dataplatform/databricks/` | `http` (retrying client), `clusters`, `unity_catalog`, `jobs_deployer`, `delta_maintenance`, `token_rotation`, `adf_monitor`, `readers` |
| `src/dataplatform/cli.py` | argparse CLI (`etl run`, `dq run`, `jobs deploy`, `maintenance run`) |
| `notebooks/01..06_*.py` | Databricks notebooks (source format) for each pipeline stage |
| `tests/` | pytest suite; `conftest.py` provides the session-scoped local SparkSession and fixtures |

## Running the tests

```bash
pytest -q                       # everything
pytest -q -m "not spark"        # pure-Python tests only (config, clients, deployer, CLI parsing)
pytest -q tests/test_scd2_merge.py -k merge
pytest --cov=dataplatform --cov-report=term-missing
```

The `spark` marker tags tests that start the local session. If no Java runtime is found the
Spark tests are skipped automatically rather than failing, so the non-Spark part of the
suite still runs on a minimal CI agent. Worker and driver interpreters are pinned to
`sys.executable` by `get_spark(local=True)` to avoid the classic Python-version mismatch
between the driver and PySpark workers.

## Design decisions

**Pure transforms, thin orchestration.** Everything in `etl/transforms.py`,
`etl/aggregations.py` and the `transform_*` / `build_*` functions takes a DataFrame and
returns a DataFrame. They have no knowledge of paths, formats or the SparkSession, so a test
can feed a five-row DataFrame and assert on exact values in milliseconds. The `run_*`
functions and notebooks only add reading and writing. This is the single biggest lever for
making a Spark codebase testable.

**Explicit schemas and quarantine over schema inference.** Inference is non-deterministic
across files and silently widens types; an explicit DDL per dataset plus PERMISSIVE parsing
means a bad file never breaks a run and never corrupts bronze. Malformed rows keep their raw
text in `_corrupt_record` so they can be triaged and replayed.

**YAML for configuration and expectations.** Environment settings, dataset definitions, job
definitions and quality rules are all declarative files that can be reviewed in a pull
request, promoted unchanged across environments and edited by people who do not write
Python. Code reads them through typed dataclasses so typos fail fast with a clear message.

**Hash-diff SCD2 in one MERGE.** Comparing a SHA-256 of the tracked columns is cheaper and
less error-prone than comparing N columns with null-safe equality, and the two-row staging
trick lets expiry and insert happen in a single atomic Delta transaction. New keys appear
once in the staged set, so they are never double inserted; the test suite checks this.

**Data quality as a gate, not a report.** The DQ task sits between silver and gold in the
job graph and raises `DataQualityError` on blocking failures; `severity: warn` rules are
reported but do not block. Results are serialisable (`to_dict` / `to_json`) and the notebook
appends them to a Delta audit table for trending.

**Databricks SDK first, REST fallback.** Jobs and token APIs use `databricks-sdk` because
its typed models (`JobSettings.from_dict`) validate definitions before they reach the
workspace. Simpler read-mostly endpoints go through a 100-line `HttpClient` with exponential
backoff and `Retry-After` handling, which keeps those clients dependency-light and fully
testable with mocked HTTP. Nothing in the package calls the network during tests.

**Safety rails on destructive operations.** `DeltaMaintenanceRunner` refuses tables outside
an allow-list and VACUUM retention below seven days unless explicitly overridden; the cluster
manager and jobs deployer default to dry-run; token rotation revokes a freshly created PAT if
the Key Vault write fails so no unreferenced credential is left alive.

## Deployment

The package is built as a wheel and attached to job clusters, or deployed with the
Databricks Asset Bundle in [`../databricks-bundles/`](../databricks-bundles/). The job
graph (`landing_to_bronze -> bronze_to_silver -> data_quality_gate -> silver_to_gold`) is
defined once in `config/jobs/medallion_pipeline.yml` and rendered per environment by
`dataplatform jobs deploy`.
