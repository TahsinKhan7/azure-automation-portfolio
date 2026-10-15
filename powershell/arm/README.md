# PowerShell: ARM validation and release tooling

Scripts that implement the validation chain for `arm-templates/` and are called by the Azure DevOps
step templates in `azure-devops-pipelines/templates/steps/`. Each runs locally with the same arguments
the pipeline uses, so an engineer can reproduce a pipeline failure on a laptop.

What this folder demonstrates: production PowerShell with comment-based help, parameter validation,
structured output objects, pipeline logging commands (`##vso[...]`) and deterministic exit codes.

## Structure

| Script | Purpose | Exit codes |
|--------|---------|------------|
| `Invoke-ArmTtk.ps1` | Resolves arm-ttk (path, installed module, or pinned git clone), runs `Test-AzTemplate`, prints a results table, writes JUnit XML, honours skips from `arm-ttk.config.json` | 0 pass, 1 failures, 2 setup error |
| `Test-ArmDeployment.ps1` | Runs `Test-AzResourceGroupDeployment` for a template file or Template Spec and returns one object with `IsValid`, flattened `Errors`, timing; `-ThrowOnError` for pipelines | throws with `-ThrowOnError` |
| `Invoke-ArmWhatIf.ps1` | Runs what-if, prints the native view plus Create/Modify/Delete counts, writes a Markdown report with property-level deltas, uploads it to the build summary, exposes counts as output variables; `-FailOnDelete` gate | 0 ok, 1 deletes with `-FailOnDelete`, 2 what-if error |
| `New-ReleasePlan.ps1` | Fills `docs/release-management/release-plan-template.md` with git change list, changed files, parameter table, promotion schedule and optional what-if summary | 0 |

## How to run

```powershell
# Static analysis, no Azure context needed
./powershell/arm/Invoke-ArmTtk.ps1 -TemplatePath ./arm-templates/templates -Verbose

# Validation and what-if (Connect-AzAccount first)
$common = @{
    ParameterFile     = './arm-templates/parameters/main.iqe.parameters.json'
    ResourceGroupName = 'rg-dp-dataplatform-iqe-uks'
    Environment       = 'iqe'
}
./powershell/arm/Test-ArmDeployment.ps1 -TemplateSpecId $specId @common -ThrowOnError
./powershell/arm/Invoke-ArmWhatIf.ps1    -TemplateSpecId $specId @common -OutputPath ./whatif-iqe.md

# Single module straight from file
./powershell/arm/Invoke-ArmWhatIf.ps1 -TemplateFile ./arm-templates/templates/modules/key-vault.json `
    -ParameterFile ./tmp/kv.dev.parameters.json -ResourceGroupName rg-dp-dataplatform-dev-uks -Environment dev

# Release plan with the what-if embedded
./powershell/arm/New-ReleasePlan.ps1 -ParameterFile ./arm-templates/parameters/main.iqe.parameters.json `
    -WhatIfSummaryPath ./whatif-iqe.md -OutputPath ./release-plan-iqe.md
```

Requirements: PowerShell 7.2+, `Az.Resources` 6+ for the Azure scripts, `git` for arm-ttk cloning and
release plan history. Template overrides can be passed to the validation and what-if scripts with
`-AdditionalParameters @{ deployPrivateEndpoints = $true }`.

## Design decisions

- Scripts accept either `-TemplateFile` or `-TemplateSpecId` so the same code path serves local module
  testing and the pipeline's Template Spec flow; the pipeline passes both and the script validates that exactly one is set.
- Pipeline integration is through logging commands rather than task-specific code, so the scripts work
  unchanged in Azure Pipelines, GitHub Actions (summary upload aside) or a terminal.
- Exit codes are distinct for "the check found problems" and "the check could not run", which lets the
  pipeline tell a failed template from a broken agent.
