# Azure DevOps YAML Pipeline Templates

Production CI/CD pipeline templates for Azure DevOps covering application builds, infrastructure deployment, Databricks notebook promotion, Data Factory ARM deployment and Terraform IaC workflows.

| Pipeline | Purpose |
|----------|---------|
| `ci-pipeline.yml` | Continuous integration with build, test, lint and artifact publish |
| `cd-pipeline.yml` | Continuous deployment with environment promotion and approval gates |
| `databricks-deploy.yml` | Deploy Databricks notebooks, jobs and libraries across workspaces |
| `terraform-plan-apply.yml` | Terraform plan with manual approval gate before apply |
| `adf-pipeline-deploy.yml` | Deploy Azure Data Factory ARM templates with pre/post deployment scripts |

## Usage

Reference these templates in your `azure-pipelines.yml`:

```yaml
resources:
  repositories:
    - repository: templates
      type: git
      name: azure-automation-portfolio

extends:
  template: azure-devops-pipelines/ci-pipeline.yml@templates
```
