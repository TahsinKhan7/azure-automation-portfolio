<!--
  GitHub profile README.

  How to use:
  1. Create a new PUBLIC repository named exactly  TahsinKhan7  (the same as the GitHub username).
     GitHub treats that repository as special and shows its README on the profile page.
  2. Copy this file into that repository as README.md (root of the repository).
  3. Commit and push. The profile page updates within a minute.

  Keep this file in sync by hand; it is stored here so the portfolio and the profile tell the same story.
-->

# Tahsin Khan

**Azure DevOps and Data Engineer, London.** Building Azure data platforms since 2019: infrastructure as code with real validation gates, pipelines that publish evidence for approvers, and PySpark that is unit-tested before it reaches a workspace.

I have spent the last few years in enterprise financial services and consultancy settings, taking Databricks lakehouses, Data Factory ingestion and the surrounding platform (Key Vault, networking, AKS, monitoring) from pull request to production through governed multi-environment pipelines.

## What I work with

- **Cloud and platform**: Microsoft Azure, Azure Databricks, Azure Data Factory, ADLS Gen2, Azure SQL, Key Vault, Log Analytics, AKS
- **Delivery**: Azure DevOps (multi-stage YAML, Environments, approvals), GitHub Actions, trunk-based delivery, Conventional Commits
- **Infrastructure as code**: Terraform (modules, native tests, OIDC backends), Bicep, ARM JSON (ARM-TTK, Template Specs, what-if)
- **Data engineering**: Python, PySpark, Delta Lake (MERGE, SCD2, liquid clustering), Databricks Asset Bundles, Delta Live Tables, Unity Catalog, SQL (T-SQL and Spark SQL)
- **Automation and operations**: PowerShell (modules, Pester, PSScriptAnalyzer), Bash, KQL for Azure Monitor alerting
- **Containers**: Kubernetes on AKS with Kustomize, workload identity and the Secrets Store CSI driver

## Featured: [azure-automation-portfolio](https://github.com/TahsinKhan7/azure-automation-portfolio)

A production-style Azure lakehouse platform promoted through five environments (`dev -> ite -> iqe -> preprod -> prod`), with every technology validated in CI.

- **Data**: a pip-installable `dataplatform` package implementing landing -> bronze -> silver -> gold on Delta Lake with a YAML-driven data quality gate and hash-diff SCD2; 141 pytest tests run on a local Delta-enabled Spark session, deployed with a Databricks Asset Bundle.
- **Infrastructure**: the same platform in Terraform (11 modules, byte-identical environment roots, 14 native test runs against a mock provider), Bicep (`bicep build` clean across templates and five parameter files) and ARM JSON (ARM-TTK and what-if gates with a documented release process).
- **Delivery and operations**: Azure Pipelines with artefact promotion and approvals on Environments, a GitHub Actions workflow with one aggregated status, a PowerShell module with 72 Pester tests, hardened AKS manifests validated with kubeconform, and KQL alerting for Data Factory, Databricks, Key Vault and cost.

## Currently

Open to Azure DevOps / Platform Engineering and Data Engineering roles in London or remote across the UK.

[LinkedIn](https://linkedin.com/in/tahsinkhan4)
