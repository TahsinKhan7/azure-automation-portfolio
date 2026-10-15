# Documentation

| Document | What it covers |
|----------|----------------|
| [architecture.md](architecture.md) | Lakehouse layers, platform layer, environment strategy, security model, observability, cost controls |
| [adr/0001-medallion-on-delta.md](adr/0001-medallion-on-delta.md) | Why landing/bronze/silver/gold on Delta Lake with a blocking data quality gate |
| [adr/0002-five-environment-promotion.md](adr/0002-five-environment-promotion.md) | Why five environments, build-once promotion and approvals on Azure DevOps Environments |
| [adr/0003-terraform-modules-with-identical-roots.md](adr/0003-terraform-modules-with-identical-roots.md) | Why Terraform roots are byte-identical and state is isolated per environment |
| [adr/0004-arm-json-alongside-bicep.md](adr/0004-arm-json-alongside-bicep.md) | Why ARM JSON, Bicep and Terraform all exist in one repository |
| [adr/0005-testing-strategy.md](adr/0005-testing-strategy.md) | What is tested offline per technology and what is proven with deployment evidence |
| [release-management/](release-management/) | Operational release process for infrastructure changes |
| [release-management/deployment-runbook.md](release-management/deployment-runbook.md) | Pull request to prod: roles, approvals per stage, what-if review checklist, failure handling, evidence retention |
| [release-management/environment-matrix.md](release-management/environment-matrix.md) | The five environments side by side: purpose, approvals, data classification, change windows, parameter differences |
| [release-management/release-plan-template.md](release-management/release-plan-template.md) | Tokenised release plan filled by `powershell/arm/New-ReleasePlan.ps1` |

Folder-level READMEs describe each technology area in detail: [arm-templates](../arm-templates/README.md), [arm-bicep](../arm-bicep/README.md), [azure-devops-pipelines](../azure-devops-pipelines/README.md), [databricks-bundles](../databricks-bundles/README.md), [kql-queries](../kql-queries/README.md), [kubernetes](../kubernetes/README.md), [powershell](../powershell/README.md), [python](../python/README.md), [scripts/ci](../scripts/ci/README.md), [sql](../sql/README.md), [terraform](../terraform/README.md).

Contribution conventions are in [CONTRIBUTING.md](../CONTRIBUTING.md); the security policy is in [.github/SECURITY.md](../.github/SECURITY.md).
