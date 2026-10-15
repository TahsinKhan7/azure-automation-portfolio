# Release management

Operational documentation for promoting infrastructure changes through the five data platform
environments. These documents are what turn the ARM templates and pipeline in this repository into a
controlled release process: who approves what, what evidence is kept, and how a change is reversed.

What this folder demonstrates: structured change management for infrastructure as code, with
what-if review as the approval artefact and a documented promotion chain from dev to prod.

## Structure

| File | Purpose |
|------|---------|
| `release-plan-template.md` | Tokenised template filled by `powershell/arm/New-ReleasePlan.ps1`; the document approvers sign |
| `deployment-runbook.md` | How a change moves from pull request to prod, who approves each stage, what evidence is captured, failure handling |
| `environment-matrix.md` | The five environments side by side: purpose, subscription placeholder, approvals, data classification, change windows, parameter differences |

## How to use

1. Generate a plan for the target environment from its parameter file:
   ```bash
   pwsh powershell/arm/New-ReleasePlan.ps1 \
     -ParameterFile arm-templates/parameters/main.preprod.parameters.json \
     -WhatIfSummaryPath whatif-preprod.md -OutputPath plans/release-plan-preprod.md
   ```
   The pipeline does the same automatically in its Quality stage and publishes the `release-plan` artefact.
2. Follow `deployment-runbook.md` for the run itself.
3. After a preprod or prod release, commit the completed plan under `plans/` as the audit record.

## Design decisions

- The release plan is generated from the parameter file and git history rather than written by hand,
  so the change list and parameter table are always accurate and the engineer only writes the summary and risk sections.
- What-if output is the unit of approval. Approvers sign off a concrete list of resource changes, not a description of intent.
- Approvers are attached to Azure DevOps Environments, not to YAML, so governance changes do not require code changes.
