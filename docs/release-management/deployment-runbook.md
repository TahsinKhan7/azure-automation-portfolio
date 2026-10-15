# Deployment runbook: ARM releases for the data platform

This runbook describes how an infrastructure change moves from a pull request to production using
the `arm-validate-deploy` pipeline. It is written for the engineer running the release and for the
approvers who need to know what they are signing off.

## At a glance

```
PR opened ──► Quality (ARM-TTK, static checks) ──► dev what-if (validate only) ──► review ──► merge
                                                                                              │
main ──► Quality ──► dev ──► ite ──► iqe ──► preprod ──► prod                                 ▼
                     auto    auto    approval  approval  approval + manual what-if sign-off
                                               no deletes no deletes
```

Every environment runs the same five steps: publish Template Spec version, validate, what-if,
(approval), deploy. The templates are packaged once in the Quality stage and never re-read from
source, so dev and prod deploy byte-identical JSON; only the parameter file differs.

## Roles

| Role | Responsibilities |
|------|------------------|
| Release engineer | Raises the PR, generates the release plan, runs the pipeline, performs post-deployment checks |
| Peer reviewer | Reviews the PR diff, the dev what-if attached to the PR build, and the parameter changes |
| Platform lead | Approves iqe and preprod Environment checks |
| Change manager | Confirms the change record and window for preprod and prod |
| Service owner | Approves the prod Environment check and resumes the ManualValidation task |
| On-call engineer | Aware of prod deployments; first responder if post-deployment checks fail |

## 1. Prepare the change

1. Branch from `main`; change templates, modules or parameter files under `arm-templates/`.
2. Run the local loop before pushing:
   ```bash
   python3 arm-templates/tests/check_templates.py
   pwsh powershell/arm/Invoke-ArmTtk.ps1 -TemplatePath arm-templates/templates
   pwsh powershell/arm/Invoke-ArmWhatIf.ps1 -TemplateFile arm-templates/templates/main.json \
        -ParameterFile arm-templates/parameters/main.dev.parameters.json \
        -ResourceGroupName rg-dp-dataplatform-dev-uks -Environment dev
   ```
   Local what-if of `main.json` needs the modules published as a Template Spec (see
   `arm-templates/README.md`); individual modules can be what-if'd directly from file.
3. Generate the release plan and commit it alongside the change when the release targets iqe or above:
   ```bash
   pwsh powershell/arm/New-ReleasePlan.ps1 -ParameterFile arm-templates/parameters/main.prod.parameters.json
   ```
4. Open the PR. The PR build runs the Quality stage and a validate-only dev stage; the dev what-if
   appears in the build summary tab and as the `whatif-dev` artefact.

## 2. Review

The reviewer checks three things, in this order:

1. **Parameter diffs** — a change to `storageSkuName`, `enableKeyVaultPurgeProtection`,
   `deployPrivateEndpoints` or `allowedIpRanges` is a platform change even when no template changed.
2. **What-if for dev** — every Create/Modify/Delete is explained by the PR description. Modify entries
   caused by Azure normalising values (for example resource type casing) are noted as noise, not approved as changes.
3. **ARM-TTK results** — new skips in `arm-ttk.config.json` need a reason and reviewer agreement.

## 3. Promotion

Merging to `main` starts the promotion run. Use the `deployThroughTo` parameter to stop early, for
example `iqe` to let a change soak for a day before continuing with a second run.

| Stage | Trigger to proceed | Evidence captured |
|-------|--------------------|-------------------|
| Quality | Automatic | ARM-TTK test results (Tests tab), `release-plan` artefact, `arm-templates` artefact |
| dev | Automatic when validate and what-if succeed | `validation-dev`, `whatif-dev`, `deployment-outputs-dev` artefacts |
| ite | Automatic | Same artefacts suffixed `-ite` |
| iqe | `iqe` Environment approval: platform lead | Approval recorded on the Environment; artefacts `-iqe` |
| preprod | `preprod` Environment approval: platform lead + change manager; what-if must contain no deletes | Approval record, change record number in the approval comment, artefacts `-preprod` |
| prod | `prod` Environment approval: service owner, business-hours check; ManualValidation resumed after reading the what-if; no deletes | Approval record, ManualValidation comment, artefacts `-prod`, release plan approvals section completed |

Approvers do not approve from the email notification alone. The expected approval comment is:

```
Change CHG0000000. Reviewed whatif-<env>: N create, N modify, 0 delete, matches release plan <id>.
```

### What-if review checklist for approvers

- Open the run, **Summary** tab, section *What-if analysis: dataplatform <env>*.
- Counts match the release plan. Any `Delete` must be listed in the plan's "Deletes approved" table.
- `Modify` entries on these properties are always deliberate and need a reason in the PR:
  `properties.networkAcls.*`, `properties.publicNetworkAccess`, `properties.enablePurgeProtection`,
  `sku.name`, `properties.retentionInDays`.
- Private endpoint resources appear only in preprod and prod (`deployPrivateEndpoints`).
- If the what-if is older than 24 hours (for example a run paused overnight) re-run the stage so the
  analysis reflects the current state of the resource group.

## 4. Deployment and verification

The deploy job runs `az deployment group create --mode Incremental` from the Template Spec version
published in the same stage, then:

1. Confirms `provisioningState == Succeeded` for the parent deployment.
2. Lists nested module deployments and fails if any operation reports `Failed`.
3. Lists resources tagged with the environment as a quick inventory.
4. Publishes deployment outputs as `deployment-outputs-<env>` for downstream pipelines.

The release engineer then completes the post-deployment table in the release plan (ADF linked
service tests, Databricks cluster start, diagnostics flowing, smoke pipeline).

## 5. When something fails

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| ARM-TTK fails on `apiVersions Should Be Recent` | arm-ttk pinned ref knows newer API versions | Update the API version in the module; do not add a skip |
| Validation fails with `InvalidTemplateDeployment` | Parameter value outside `allowedValues`/`minValue` or missing Key Vault reference | Fix the parameter file; check the bootstrap vault secret exists |
| What-if shows unexpected `Delete` of `securityRules` | NSG rules were changed in the portal | Hotfix drift via the template, never approve a delete to "clean up" |
| What-if shows `Modify` on `uniqueString` names | Resource group was recreated, so `resourceNameSuffix` changed | Pass the previous suffix explicitly through `resourceNameSuffix` |
| Deployment fails in `*-keyvault-access` | Service connection lacks `User Access Administrator` on the group | Grant the role or remove the extra principal IDs |
| Databricks module fails with subnet delegation error | Subnets already used by another workspace | Deploy a fresh VNet prefix for the environment |
| Deployment succeeded but post-deployment verification failed | Nested operation retried and left a `Failed` record | Inspect `az deployment operation group list`; re-run the stage once |

Rollback is a redeployment of the previous Template Spec version (see the release plan template,
section 7). Never delete resources to roll back an ARM release.

## 6. Evidence retention

Pipeline artefacts, test results and Environment approval records are retained with the run.
Release plans for preprod and prod are committed to `docs/release-management/plans/` after the
release with the approvals section completed, so the audit trail does not depend on pipeline retention.
