# Azure Pipelines templates: ARM validate and deploy

Reusable YAML templates behind `azure-devops-pipelines/arm-validate-deploy.yml`. The stage template
encapsulates the whole per-environment flow, so adding a sixth environment is a ten-line change in the
pipeline file and nothing else.

What this folder demonstrates: layered pipeline templates (steps, jobs, stages), deployment jobs bound
to Azure DevOps Environments for approvals, agentless manual validation, runtime output variables flowing
between jobs, and artefact-based promotion so every environment deploys the same package.

## Structure

| Template | Type | Purpose |
|----------|------|---------|
| `steps/arm-ttk.yml` | steps | Runs `Invoke-ArmTtk.ps1`, publishes JUnit results to the Tests tab |
| `steps/arm-publish-template-spec.yml` | steps | `az ts create` for `main.json` and its linked modules; exposes `PublishTemplateSpec.templateSpecId` |
| `steps/arm-validate.yml` | steps | `Test-ArmDeployment.ps1` against the Template Spec; publishes `validation-<env>` |
| `steps/arm-whatif.yml` | steps | `Invoke-ArmWhatIf.ps1`; Markdown to build summary and `whatif-<env>` artefact; counts as output variables; optional fail-on-delete |
| `jobs/arm-deploy.yml` | deployment job | `environment: <env>` for approvals; `az deployment group create` from the Template Spec; post-deployment verification; outputs published and exposed as job outputs |
| `stages/arm-environment-stage.yml` | stage | Validate -> what-if -> optional `ManualValidation@0` -> deploy; `validateOnly` mode for pull requests |

## How to use

```yaml
stages:
  - template: templates/stages/arm-environment-stage.yml
    parameters:
      environment: preprod
      dependsOn: [Deploy_iqe]
      serviceConnection: sc-dp-dataplatform-preprod
      resourceGroupName: rg-dp-dataplatform-preprod-uks
      templateSpecResourceGroup: rg-dp-templatespecs-preprod-uks
      variableGroup: dp-arm-preprod
      failOnDelete: true
      requireManualValidation: false
```

Prerequisites per environment: a service connection with Contributor and User Access Administrator on
the platform resource group, an Azure DevOps Environment named after the environment code with the
approvals from `docs/release-management/environment-matrix.md`, and the `arm-templates` artefact
produced by a preceding Quality stage.

## Parameter reference (stage template)

| Parameter | Default | Notes |
|-----------|---------|-------|
| `environment` | required | `dev`, `ite`, `iqe`, `preprod`, `prod`; also the Environment name and artefact suffix |
| `dependsOn` / `condition` | `[]` / `succeeded()` | Chain stages and gate on branch, reason or the `deployThroughTo` parameter |
| `serviceConnection`, `resourceGroupName`, `templateSpecResourceGroup` | required | Per-environment Azure targets |
| `parameterFile` | `parameters/main.<env>.parameters.json` | Relative to the `arm-templates` artefact root |
| `variableGroup` | none | Linked at stage scope |
| `requireManualValidation` | `false` | Adds an agentless `ManualValidation@0` job between what-if and deploy |
| `failOnDelete` | `false` | What-if deletes fail the stage |
| `validateOnly` | `false` | Skip manual validation and deployment (pull request runs) |

## Design decisions

- Approvals live on Environments, not in YAML. The YAML only decides *where* a gate sits; *who* approves is governed outside the code.
- Templates are packaged once and republished as a Template Spec per subscription, giving each environment an immutable, auditable version while keeping linked modules as separate files.
- Validation and what-if run in a normal job, deployment in a deployment job. Approval prompts therefore arrive with the what-if already attached to the run, and no Environment approval is consumed just to find out that a template is invalid.
