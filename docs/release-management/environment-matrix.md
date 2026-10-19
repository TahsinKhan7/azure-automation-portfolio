# Environment matrix

The data platform runs five long-lived environments. The same ARM templates serve all of them; the
differences below are expressed entirely through `arm-templates/parameters/main.<env>.parameters.json`
and through the approvals configured on the matching Azure DevOps Environment.

Subscription IDs are placeholders; real values live in the `dp-arm-<env>` variable groups.

| Environment | Purpose | Subscription (placeholder) | Resource group | Approvals to deploy | Data classification | Change window |
|-------------|---------|----------------------------|----------------|---------------------|---------------------|---------------|
| `dev` | Engineering sandbox; Git-backed Data Factory; short retention | `00000000-0000-0000-0000-00000000d0e1` | `rg-dp-dataplatform-dev-uks` | None (automatic after validation and what-if) | Internal, synthetic data only | Any time |
| `ite` | Integration test environment; automated pipeline and contract tests run here after each merge | `00000000-0000-0000-0000-0000000017e1` | `rg-dp-dataplatform-ite-uks` | None (automatic) | Internal, synthetic and masked samples | Any time |
| `iqe` | Integration quality environment; QA sign-off, performance baselines, UAT rehearsals | `00000000-0000-0000-0000-0000000019e1` | `rg-dp-dataplatform-iqe-uks` | Platform lead (Environment approval) | Confidential, masked production extracts | Mon-Fri 08:00-18:00 |
| `preprod` | Production mirror: same SKUs, private endpoints, retention and firewall posture as prod | `00000000-0000-0000-0000-00000000b4e1` | `rg-dp-dataplatform-preprod-uks` | Platform lead + change manager; what-if must contain no deletes | Confidential, full production copy (access controlled) | Tue/Thu 18:00-21:00 |
| `prod` | Live platform serving analytics and downstream consumers | `00000000-0000-0000-0000-00000000b0d1` | `rg-dp-dataplatform-prod-uks` | Service owner (Environment approval, business-hours check) + ManualValidation what-if sign-off + CAB record; no deletes | Confidential | Tue/Thu 19:00-22:00, CAB approved; freeze periods at month and year end |

## Parameter differences by environment

| Parameter | dev | ite | iqe | preprod | prod |
|-----------|-----|-----|-----|---------|------|
| `vnetAddressPrefix` | 10.10.0.0/16 | 10.11.0.0/16 | 10.12.0.0/16 | 10.20.0.0/16 | 10.30.0.0/16 |
| `storageSkuName` | Standard_LRS | Standard_LRS | Standard_ZRS | Standard_GZRS | Standard_RAGZRS |
| `coolTierAfterDays` / `deleteLandingAfterDays` | 7 / 14 | 7 / 14 | 14 / 30 | 30 / 90 | 30 / 180 |
| `logRetentionInDays` | 30 | 30 | 30 | 90 | 365 |
| `logDailyQuotaGb` | 2 | 2 | 5 | 10 | unlimited |
| `keyVaultSkuName` | standard | standard | standard | standard | premium |
| `enableKeyVaultPurgeProtection` | false | false | true | true | true |
| `databricksPricingTier` | premium | premium | premium | premium | premium |
| `enableDataFactoryGit` | true | false | false | false | false |
| `deployPrivateEndpoints` | false | false | false | true | true |
| Soft-delete retention (derived) | 7 days | 7 days | 7 days | 30/90 days | 30/90 days |

Derived values (`isProductionLike`, soft-delete retention, DBFS root replication) are computed in
`main.json` from the `environment` parameter, so they cannot drift between preprod and prod.

## Azure DevOps configuration per environment

| Item | Naming | Notes |
|------|--------|-------|
| Service connection | `sc-dp-dataplatform-<env>` | Workload identity federation; Contributor + User Access Administrator on the platform resource group only |
| Variable group | `dp-arm-<env>` | Subscription ID, bootstrap Key Vault name, notification lists; no secrets |
| Environment | `<env>` | Approvals and checks as in the matrix; exclusive lock on preprod and prod |
| Template Spec resource group | `rg-dp-templatespecs-<env>-uks` | Holds `dataplatform-landing-zone` versions, one per pipeline run |
| Bootstrap Key Vault | `kv-dp-bootstrap-<env>` | Pre-existing; supplies `dataplatform-sp-client-secret` via parameter file reference |

## Access model

| Principal | dev / ite | iqe | preprod | prod |
|-----------|-----------|-----|---------|------|
| Platform engineers | Contributor | Reader + JIT Contributor | Reader | Reader |
| Pipeline service connection | Contributor + UAA on platform RG | Same | Same | Same |
| Data engineers | Contributor on Databricks and ADF | Databricks user | Databricks user | None (read via Power BI) |
| Analysts | None | Storage Blob Data Reader (gold) | Storage Blob Data Reader (gold) | Storage Blob Data Reader (gold) |

Changes to this matrix are reviewed like code: update the parameter files and this document in the
same pull request.
