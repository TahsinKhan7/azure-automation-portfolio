# key-vault

**What this demonstrates:** a Key Vault configured for RBAC authorisation, deny-by-default networking, purge protection and audit logging, with role assignments for administrators and secret readers expressed as inputs.

## Structure

| File | Purpose |
|------|---------|
| `main.tf` | Vault, role assignments, diagnostic setting |
| `variables.tf` | Name regex, SKU, retention, network ACLs, principal sets, diagnostics toggle |
| `outputs.tf` | ID, name, URI and tenant |
| `versions.tf` | Terraform and provider version constraints |

## Usage

```hcl
module "key_vault" {
  source                   = "../../modules/key-vault"
  name                     = module.naming.key_vault
  resource_group_name      = module.resource_group.name
  allowed_ip_ranges        = ["203.0.113.10"]
  administrator_object_ids = ["<platform admins group>"]
  secrets_user_object_ids  = ["<aks workload identity>"]
  enable_diagnostics         = true
  log_analytics_workspace_id = module.log_analytics.id
}
```

Validate on its own with `terraform -chdir=terraform/modules/key-vault init -backend=false && terraform -chdir=terraform/modules/key-vault validate`.

## Design decisions

- RBAC rather than access policies: permissions are reviewable with every other role assignment and can target groups.
- Purge protection is on by default and only disabled through an explicit variable, because enabling it is irreversible and the safe default is the protective one.
- `enable_diagnostics` is a boolean separate from the workspace ID so the resource count is known at plan time during a first apply.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Key Vault name (3-24 alphanumerics and hyphens, globally unique). | `string` | n/a | yes |
| `resource_group_name` | Resource group the vault is created in. | `string` | n/a | yes |
| `location` | Azure region. | `string` | `uksouth` | no |
| `sku_name` | Vault SKU. premium adds HSM-backed keys. | `string` | `standard` | no |
| `soft_delete_retention_days` | Days a deleted vault or secret can be recovered (7-90). | `number` | `90` | no |
| `purge_protection_enabled` | Prevent permanent deletion during the retention window. Irreversible once enabled; keep true outside of dev. | `bool` | `true` | no |
| `public_network_access_enabled` | Allow access from public networks (subject to network_acls). Set false when a private endpoint is deployed. | `bool` | `true` | no |
| `network_acls_default_action` | Default firewall action for traffic not matched by an IP or subnet rule. | `string` | `Deny` | no |
| `allowed_ip_ranges` | Public IP addresses or CIDR ranges allowed through the vault firewall (for example build agents). | `list(string)` | `[]` | no |
| `allowed_subnet_ids` | Subnet IDs allowed through the vault firewall via the Microsoft.KeyVault service endpoint. | `list(string)` | `[]` | no |
| `administrator_object_ids` | Entra ID object IDs granted Key Vault Administrator. Normally the platform team group and the deployment identity. | `set(string)` | `[]` | no |
| `secrets_user_object_ids` | Entra ID object IDs granted Key Vault Secrets User (read secrets). Typically workload managed identities. | `set(string)` | `[]` | no |
| `enable_diagnostics` | Create the diagnostic setting. Kept separate from log_analytics_workspace_id so that the toggle is known at plan time even when the workspace is created in the same apply. | `bool` | `false` | no |
| `log_analytics_workspace_id` | Workspace ID for audit diagnostics. Required when enable_diagnostics is true. | `string` | `null` | no |
| `tags` | Tags applied to the vault. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Key Vault resource ID. |
| `name` | Key Vault name. |
| `vault_uri` | Vault URI, for example https://kv-dp-data-dev-01.vault.azure.net/. |
| `tenant_id` | Tenant the vault belongs to. |
