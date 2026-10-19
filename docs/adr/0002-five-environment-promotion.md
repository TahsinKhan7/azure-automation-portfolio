# ADR 0002: Five environments with artefact promotion and approvals on Environments

Status: accepted

## Context

Enterprise platforms need separate stages for feature work, integration, formal quality assurance, a production rehearsal and production itself, each with different approvers, data classification and change windows. Rebuilding code per environment, or keeping long-lived environment branches, is a common source of "it worked in UAT" incidents.

## Decision

Use five environments, always in this order: `dev -> ite -> iqe -> preprod -> prod`. Build once; promote the same artefact (wheel and notebooks, saved Terraform plan, Template Spec version, rendered manifests) through each stage. Generate the stages from a single template loop so the promotion path is declared once. Attach approvals, exclusive locks, business-hours windows and branch control to Azure DevOps Environments rather than encoding them in YAML. Treat `preprod` as production-like by default: private endpoints, GZRS, purge protection, delete locks and fail-on-delete what-if are switched on there as well as in `prod`.

Implementation: [`azure-devops-pipelines/`](../../azure-devops-pipelines/), [`docs/release-management/environment-matrix.md`](../release-management/environment-matrix.md), [`docs/release-management/deployment-runbook.md`](../release-management/deployment-runbook.md).

## Consequences

- Governance changes (who approves `prod`) require no code change and no redeploy.
- A no-op plan or what-if skips its apply stage, so approvers are only asked when something will change.
- Every environment carries its own cost; `dev` runs spot compute with paused schedules and short retention to offset it.
- Five parameter sets must stay in parity; [`arm-templates/tests/check_templates.py`](../../arm-templates/tests/check_templates.py) and identical Terraform roots enforce that mechanically.
- Hotfixes still travel the full path from `main`; a dedicated redeploy pipeline exists for rolling a single environment back to a known-good build.
