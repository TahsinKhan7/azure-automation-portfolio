# Databricks Asset Bundle - dataplatform

This folder shows how the [`python/`](../python/) package, its notebooks and its job graph are
deployed to Databricks as a single versioned unit using **Databricks Asset Bundles (DABs)**:
one `databricks.yml`, five targets (dev, ite, iqe, preprod, prod), environment differences
expressed only as variables, and the same command used by a laptop and by CI.

## What it demonstrates

- Multi-task job with explicit dependencies and a **data quality gate** between silver and gold
  (`resources/jobs/medallion_pipeline.yml`).
- Job clusters with Photon, autoscaling, **spot with on-demand fallback** in non-prod and
  on-demand in prod, a cluster policy for cost control, retries, health rules and e-mail /
  webhook notifications.
- Weekly Delta maintenance job (`resources/jobs/delta_maintenance.yml`).
- An optional **Delta Live Tables** pipeline (`resources/pipelines/claims_dlt_pipeline.yml`,
  `src/dlt_claims_pipeline.py`) using `@dlt.table` and `@dlt.expect_*` for the same flow.
- A cluster policy JSON (`resources/clusters/job_cluster_policy.json`) that pins runtimes,
  node types, autoscale ranges, auto-termination and tags.
- `mode: development` for dev (prefixed resource names, paused schedules, deploy as yourself)
  and `mode: production` with `run_as` a service principal for everything else.

## Structure

```
databricks-bundles/
├── databricks.yml                         # bundle, variables, artifacts, sync, targets
├── resources/
│   ├── jobs/
│   │   ├── medallion_pipeline.yml         # landing -> bronze -> silver -> DQ gate -> gold / SCD2
│   │   └── delta_maintenance.yml          # weekly OPTIMIZE / ZORDER / VACUUM
│   ├── pipelines/
│   │   └── claims_dlt_pipeline.yml        # DLT alternative for claims
│   └── clusters/
│       └── job_cluster_policy.json        # cost-control cluster policy
└── src/
    └── dlt_claims_pipeline.py             # DLT notebook (source format)
```

The job tasks reference `../../python/notebooks/*.py` and the wheel built from `../python`,
so the bundle deploys the exact code that the unit tests ran against.

## How to run

```bash
# one-off: authenticate (PAT, Azure CLI or service principal via env vars)
databricks auth login --host https://adb-0000000000000001.1.azuredatabricks.net

cd databricks-bundles
databricks bundle validate -t dev          # renders and checks every resource
databricks bundle deploy   -t dev          # builds the wheel, syncs notebooks/config, creates jobs
databricks bundle run      -t dev medallion_pipeline
databricks bundle run      -t dev delta_maintenance --no-wait
databricks bundle summary  -t dev          # URLs of deployed resources
databricks bundle destroy  -t dev          # tidy up a personal dev deployment
```

Override a variable without editing YAML:

```bash
databricks bundle deploy -t ite --var="max_workers=6"
```

## Promotion path

| Target | Mode | Runs as | Compute | Schedules |
|--------|------|---------|---------|-----------|
| `dev` | development | the deploying user | spot w/ fallback, 1-2 workers | paused |
| `ite` | production | service principal | spot w/ fallback, 1-4 | active |
| `iqe` | production | service principal | spot w/ fallback, 2-4 | active |
| `preprod` | production | service principal | on-demand, 2-8 | active |
| `prod` | production | service principal, explicit permissions | on-demand, 2-12 | active |

Promotion is the same artefact deployed to the next target; nothing is rebuilt or edited
between environments. Secrets never appear in the bundle: workspace hosts are placeholders,
the service principal is referenced by client ID only, and credentials are supplied by the
CI identity.

## CI integration

A typical pipeline (Azure DevOps or GitHub Actions) runs:

1. `cd python && pip install -e ".[dev]" && ruff check . && pytest -q` - unit tests on a local
   Spark session, no workspace needed.
2. `databricks bundle validate -t <target>` on every pull request.
3. `databricks bundle deploy -t dev` on merge to the main branch.
4. `databricks bundle deploy -t ite|iqe|preprod|prod` from the release pipeline, each stage
   gated by an environment approval, authenticating as the service principal with
   `ARM_CLIENT_ID` / `ARM_CLIENT_SECRET` / `ARM_TENANT_ID` (or workload identity federation).

Because `databricks bundle deploy` is idempotent, re-running a stage converges the workspace
to the committed definition rather than creating duplicates.

## Design notes

- **Variables over copies.** Every environment difference (hosts, catalog, storage account,
  worker counts, spot vs on-demand, schedule state) is a variable with a per-target override.
  The resource files are never duplicated per environment.
- **DQ gate has no retries.** A failed expectation is a data problem; retrying hides it.
  Ingestion and transform tasks retry with a back-off because their failures are usually
  transient (throttling, spot eviction).
- **Policy before cluster.** The cluster policy fixes auto-termination, caps DBUs per hour,
  forbids single-node profiles for jobs and forces the cost-allocation tags, so a mis-typed
  job definition cannot create an expensive cluster.
- **Jobs and DLT side by side.** The multi-task job uses the tested Python package; the DLT
  pipeline shows the declarative alternative with built-in expectations and lineage. Teams
  can choose per dataset.
