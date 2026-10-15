# ADR 0005: Test what can be tested offline; publish evidence for the rest

Status: accepted

## Context

Infrastructure and data code is often "tested" only by deploying it. That is slow, needs credentials, and gives no signal on a pull request. At the same time, some properties (provider quotas, name collisions, real cluster behaviour) can only be proven against Azure.

## Decision

Split every technology into a part that runs offline in CI and a part that produces reviewable evidence at deployment time.

| Technology | Offline in CI | Evidence at deployment |
|------------|---------------|------------------------|
| Python / PySpark | `ruff`, 141 pytest tests on a local Delta-enabled Spark session (PySpark 3.5, delta-spark 3.2); HTTP clients tested with mocked responses | Smoke-test job after each Databricks deploy |
| PowerShell | PSScriptAnalyzer (errors fail), 72 Pester tests in 8 files with mocked Az cmdlets | `-WhatIf` honoured by every state-changing script |
| Terraform | `fmt`, `tflint`, `validate` per directory, 14 `terraform test` runs with `mock_provider` | Saved plan reviewed and applied unchanged; destroy warnings on the run |
| ARM JSON | JSON lint, ARM-TTK, parameter parity and contract checks | `Test-AzResourceGroupDeployment`, what-if report, fail-on-delete in preprod/prod |
| Bicep | `bicep build` for every template and `.bicepparam`, linter at `error` for secrets | `az deployment group what-if` |
| Kubernetes | `kubectl kustomize` + `kubeconform -strict` for 5 overlays | `rollout status` gate, canary for prod, automatic rollback |
| SQL / YAML / Markdown | sqlfluff, yamllint, markdownlint | n/a |

Keep logic pure so the offline share is as large as possible: DataFrame-in, DataFrame-out transforms; PowerShell decisions in module functions with a `-Now` parameter where time matters; Terraform validation in `variable` and `precondition` blocks.

## Consequences

- Pull requests get a real signal in minutes without any Azure credentials; the GitHub Actions workflow needs no secrets at all.
- Approvers review concrete artefacts (plan, what-if, rendered manifests, test reports) instead of descriptions of intent.
- Mocked tests cannot catch provider-side errors, so validation and what-if remain mandatory stages before any approval.
- Test counts are a floor, not a target; new behaviour arrives with a test in the same pull request ([CONTRIBUTING.md](../../CONTRIBUTING.md)).
