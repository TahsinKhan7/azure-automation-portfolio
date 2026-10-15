# ARM templates: one template, five environments

JSON ARM templates for the data platform landing zone (network, Log Analytics, ADLS Gen2 data lake,
Key Vault, Databricks, Data Factory), deployed to `dev`, `ite`, `iqe`, `preprod` and `prod` from a
single orchestrator and one parameter file per environment. The pipeline validates every change with
ARM-TTK, deployment validation and what-if before any approval is requested.

What this folder demonstrates: linked-template composition with `Microsoft.Resources/deployments`,
`copy` loops, `condition`-gated resources, `uniqueString` naming, `secureObject`/`secureString`
handling with Key Vault parameter references, and a repeatable validation chain across six-plus environments.

## Structure

| Path | Purpose |
|------|---------|
| `templates/main.json` | Orchestrator. Builds names and tags, wires module outputs into module inputs, seeds Key Vault secrets from outputs, grants Key Vault RBAC through an inline nested template |
| `templates/modules/networking.json` | VNet, Databricks host/container subnets (delegated, NSG attached, service endpoints), private endpoint subnet, NSG rules via `copy` |
| `templates/modules/log-analytics.json` | Workspace with retention, daily cap, saved searches for ADF, Databricks, Key Vault and storage |
| `templates/modules/storage-account.json` | ADLS Gen2 with `landing/bronze/silver/gold` containers (`copy`), lifecycle tiering and expiry, firewall IP/subnet rules, diagnostics, conditional blob + dfs private endpoints |
| `templates/modules/key-vault.json` | RBAC authorisation, soft delete, optional purge protection, firewall, seeded secrets from a `secureObject`, diagnostics, conditional private endpoint |
| `templates/modules/databricks-workspace.json` | Premium workspace, VNet injection, secure cluster connectivity, diagnostics for all log categories |
| `templates/modules/data-factory.json` | Managed VNet + managed integration runtime, optional Git configuration, Key Vault and data lake linked services, global parameters, diagnostics |
| `parameters/main.<env>.parameters.json` | Identical shape across the five environments; values differ (see matrix below) |
| `arm-ttk.config.json` | ARM-TTK pinned version and documented skips, consumed by `powershell/arm/Invoke-ArmTtk.ps1` |
| `tests/check_templates.py` | Offline checks: JSON parse, parameter parity across environments, main-to-module contract, unreferenced parameters and variables |

## Environment matrix

| | dev | ite | iqe | preprod | prod |
|---|---|---|---|---|---|
| Storage replication | LRS | LRS | ZRS | GZRS | RAGZRS |
| Log retention / daily cap | 30d / 2GB | 30d / 2GB | 30d / 5GB | 90d / 10GB | 365d / none |
| Key Vault SKU / purge protection | standard / off | standard / off | standard / on | standard / on | premium / on |
| Private endpoints (storage, vault) | no | no | no | yes | yes |
| Data Factory Git-backed | yes | no | no | no | no |
| Landing zone expiry | 14d | 14d | 30d | 90d | 180d |
| Approval to deploy | automatic | automatic | platform lead | lead + change manager | service owner + manual what-if sign-off |

Full detail, including subscriptions and change windows, is in `docs/release-management/environment-matrix.md`.

## Naming convention

`main.json` derives every name from `orgPrefix`, `platformName`, `environment` and a six-character
`uniqueString(resourceGroup().id)` suffix for globally unique resources:

| Resource | Pattern | Example (dev) |
|----------|---------|---------------|
| Resource group (pipeline) | `rg-{org}-{platform}-{env}-uks` | `rg-dp-dataplatform-dev-uks` |
| Virtual network | `vnet-{org}-{platform}-{env}` | `vnet-dp-dataplatform-dev` |
| NSG | `nsg-{org}-{platform}-{env}-dbw` | `nsg-dp-dataplatform-dev-dbw` |
| Log Analytics | `log-{org}-{platform}-{env}` | `log-dp-dataplatform-dev` |
| Storage (ADLS Gen2) | `{org}{env}lake{suffix}` | `dpdevlakea1b2c3` |
| Key Vault | `kv-{org}-{env}-{suffix}` | `kv-dp-dev-a1b2c3` |
| Databricks workspace | `dbw-{org}-{platform}-{env}` | `dbw-dp-dataplatform-dev` |
| Databricks managed RG | `rg-{org}-{platform}-{env}-dbw-managed` | `rg-dp-dataplatform-dev-dbw-managed` |
| Data Factory | `adf-{org}-{platform}-{env}-{suffix}` | `adf-dp-dataplatform-dev-a1b2c3` |

Tags `environment`, `platform`, `managedBy` and `templateVersion` are added to whatever the parameter
file supplies (`costCentre`, `owner`, `dataClassification`, `changeWindow`).

## How validation works

```
ARM-TTK (static)  ->  check_templates.py (static)  ->  Test-AzResourceGroupDeployment  ->  What-if  ->  approvals  ->  deploy
powershell/arm/Invoke-ArmTtk.ps1              Test-ArmDeployment.ps1     Invoke-ArmWhatIf.ps1   ADO Environment   az deployment group create
```

1. **ARM-TTK** runs against `templates/` with the skips in `arm-ttk.config.json`. Results are published as JUnit.
2. **Static checks** confirm the five parameter files share one shape and that `main.json` passes exactly what each module declares.
3. **Template Spec publish**: `az ts create` packages `main.json` and every `relativePath` module as one versioned artefact in the target subscription.
4. **Validation** (`Test-AzResourceGroupDeployment`) catches provider-side errors: invalid SKU for region, quota, name collisions.
5. **What-if** produces the change list that approvers sign. preprod and prod fail if any `Delete` appears.
6. **Deploy** in Incremental mode from the Template Spec version, with outputs published for downstream pipelines.

The pipeline is `azure-devops-pipelines/arm-validate-deploy.yml`; the reusable stage is
`azure-devops-pipelines/templates/stages/arm-environment-stage.yml`.

## Local commands

```bash
# Offline checks (no Azure access needed)
python3 arm-templates/tests/check_templates.py
pwsh powershell/arm/Invoke-ArmTtk.ps1 -TemplatePath arm-templates/templates

# Publish the template tree as a Template Spec version in your dev subscription
az ts create --name dataplatform-landing-zone --version local-$(git rev-parse --short HEAD) \
  --resource-group rg-dp-templatespecs-dev-uks --location uksouth \
  --template-file arm-templates/templates/main.json --yes
SPEC_ID=$(az ts show --name dataplatform-landing-zone --version local-$(git rev-parse --short HEAD) \
  --resource-group rg-dp-templatespecs-dev-uks --query id -o tsv)

# Validate and what-if against dev
pwsh powershell/arm/Test-ArmDeployment.ps1 -TemplateSpecId "$SPEC_ID" \
  -ParameterFile arm-templates/parameters/main.dev.parameters.json \
  -ResourceGroupName rg-dp-dataplatform-dev-uks -Environment dev -ThrowOnError
pwsh powershell/arm/Invoke-ArmWhatIf.ps1 -TemplateSpecId "$SPEC_ID" \
  -ParameterFile arm-templates/parameters/main.dev.parameters.json \
  -ResourceGroupName rg-dp-dataplatform-dev-uks -Environment dev

# A single module can be validated straight from file
az deployment group validate --resource-group rg-dp-dataplatform-dev-uks \
  --template-file arm-templates/templates/modules/log-analytics.json \
  --parameters workspaceName=log-dp-dataplatform-dev location=uksouth
```

`main.json` links its modules with `templateLink.relativePath`, which Azure resolves only for templates
served from a URI or a Template Spec, hence the publish step above. This keeps the modules as separate,
individually testable files instead of one large inline template.

## Design decisions

- **Linked modules plus one inline nested template.** Modules stay independently testable and reusable;
  the Key Vault role assignment is inline (`expressionEvaluationOptions: inner`) because it is a few lines
  and only meaningful alongside the orchestrator.
- **Environment hardening is derived, not configured, where it matters.** `isProductionLike` in `main.json`
  drives soft-delete retention and DBFS replication so preprod cannot silently diverge from prod.
- **Secrets never appear in parameter files.** The one `secureString` is a Key Vault reference to a
  per-environment bootstrap vault; platform outputs that other systems need are written into the platform vault by the template itself.
- **Private endpoint DNS is intentionally not in these templates.** The hub registers private DNS zones
  through Azure Policy, so the spoke templates only create the endpoints.
