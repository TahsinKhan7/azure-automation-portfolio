# private-endpoints

**What this demonstrates:** a generic private endpoint factory: a single map describes any number of endpoints (resource, sub-resource, DNS zones) and the module creates each endpoint with its DNS zone group.

## Structure

| File | Purpose |
|------|---------|
| `main.tf` | `for_each` private endpoints with a dynamic DNS zone group |
| `variables.tf` | The `endpoints` map (validated to carry a sub-resource), subnet, naming prefix |
| `outputs.tf` | Endpoint IDs and allocated private IPs keyed by endpoint |
| `versions.tf` | Terraform and provider version constraints |

## Usage

```hcl
module "private_endpoints" {
  source              = "../../modules/private-endpoints"
  count               = var.enable_private_endpoints ? 1 : 0
  name_prefix         = module.naming.private_endpoint_prefix
  subnet_id           = module.networking.private_endpoint_subnet_id
  resource_group_name = module.resource_group.name

  endpoints = {
    vault = { resource_id = module.key_vault.id,       subresource_names = ["vault"], private_dns_zone_ids = [zone_id] }
    dfs   = { resource_id = module.storage_account.id, subresource_names = ["dfs"],   private_dns_zone_ids = [zone_id] }
  }
}
```

Validate on its own with `terraform -chdir=terraform/modules/private-endpoints init -backend=false && terraform -chdir=terraform/modules/private-endpoints validate`.

## Design decisions

- One generic module instead of a private endpoint block in every service module keeps the service modules small and lets each environment decide which services are privately addressed.
- The DNS zone group is dynamic so an endpoint can be created without zones (for example when DNS is handled by a central policy).
- The root decides zone membership by map key, which is known at plan time, rather than by zone ID, which is not.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `endpoints` | <<-EOT     Map of private endpoints to create, keyed by a short name that is appended to name_prefix.     Each entry names the target resource, the sub-resource (group ID) and the private DNS zones     that should receive the A record.   EOT | `map(...)` | n/a | yes |
| `name_prefix` | Prefix for private endpoint names; the map key is appended, for example pe-dp-data-prod-vault. | `string` | n/a | yes |
| `subnet_id` | Subnet the private endpoints are placed in. | `string` | n/a | yes |
| `resource_group_name` | Resource group for the private endpoints. | `string` | n/a | yes |
| `location` | Azure region. | `string` | `uksouth` | no |
| `tags` | Tags applied to the private endpoints. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `ids` | Map of endpoint key to private endpoint resource ID. |
| `private_ip_addresses` | Map of endpoint key to the allocated private IP address. |
