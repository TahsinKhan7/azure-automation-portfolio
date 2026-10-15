## Summary

<!-- What does this change do and why? Link the issue or work item if there is one. -->

Closes #

## Change type

- [ ] Infrastructure (Terraform / Bicep / ARM)
- [ ] Data platform code (Python / PySpark / Databricks bundle)
- [ ] Pipeline or workflow (Azure DevOps / GitHub Actions)
- [ ] Operations script (PowerShell / Bash / KQL)
- [ ] SQL
- [ ] Documentation only

## Environments affected

| Environment | Affected | Notes |
|-------------|:--------:|-------|
| dev         |          |       |
| ite         |          |       |
| iqe         |          |       |
| preprod     |          |       |
| prod        |          |       |

## Validation evidence

<!--
Paste or link the evidence that proves this change is safe. Remove rows that do not apply.
- Terraform: `terraform plan` summary (adds / changes / destroys) for every affected root
- Bicep / ARM: `az deployment group what-if` output
- Python: pytest / ruff output or the CI run link
- Kubernetes: `kubectl kustomize` + kubeconform output, or `kubectl diff`
- PowerShell: PSScriptAnalyzer + Pester output
-->

| Check | Result | Link / output |
|-------|--------|---------------|
| CI workflow | | |
| Plan / what-if | | |
| Tests | | |

## Rollback

<!-- How is this change reverted if it misbehaves? e.g. "revert the merge commit and re-run terraform apply", "redeploy previous wheel from pipeline run N", "kubectl rollout undo". -->

## Checklist

- [ ] No secrets, connection strings, subscription or tenant identifiers are committed
- [ ] Naming follows the `<type>-dp-<workload>-<env>` convention from the naming module and tags are set
- [ ] New or changed resources are covered by Terraform/Bicep validation and (where relevant) tests
- [ ] Documentation and READMEs updated for anything a reviewer or operator needs to know
- [ ] Breaking changes are called out in the summary and the PR title follows Conventional Commits
