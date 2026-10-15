# networking

**What this demonstrates:** the network foundation for a VNet-injected Databricks workspace: delegated host/container subnets sharing one NSG, a private endpoint subnet, optional NAT gateway for secure-cluster-connectivity egress, and optional private DNS zones for single-VNet estates.

## Structure

| File | Purpose |
|------|---------|
| `main.tf` | VNet, subnets, NSG associations, NAT gateway, private DNS zones and links |
| `variables.tf` | CIDRs validated with `cidrhost`, service endpoints, NAT and DNS toggles |
| `outputs.tf` | IDs and names the Databricks and private-endpoints modules need, NAT egress IP, DNS zone ID map |
| `versions.tf` | Terraform and provider version constraints |

## Usage

```hcl
module "networking" {
  source              = "../../modules/networking"
  vnet_name           = module.naming.virtual_network
  nsg_name            = module.naming.network_security_group
  resource_group_name = module.resource_group.name
  address_space       = ["10.14.0.0/16"]
  enable_nat_gateway  = true
  private_dns_zones   = ["privatelink.dfs.core.windows.net"]
}
```

Validate on its own with `terraform -chdir=terraform/modules/networking init -backend=false && terraform -chdir=terraform/modules/networking validate`.

## Design decisions

- Databricks populates the NSG rules itself once the subnet association exists, so the NSG is created empty and the association IDs are exported for the workspace module.
- Service endpoints for Storage and Key Vault are on by default; they let the firewalls allow the Databricks subnets even in environments without private endpoints.
- Private DNS zones are optional because in a hub-and-spoke estate they live in the hub. The root module merges hub zone IDs over locally created ones.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `vnet_name` | Virtual network name. | `string` | n/a | yes |
| `nsg_name` | Name of the network security group attached to the Databricks subnets. | `string` | n/a | yes |
| `resource_group_name` | Resource group for all networking resources. | `string` | n/a | yes |
| `location` | Azure region. | `string` | `uksouth` | no |
| `address_space` | Address space of the virtual network. | `list(string)` | `[10.0.0.0/16]` | no |
| `databricks_public_subnet_cidr` | CIDR of the Databricks host (public) subnet. | `string` | `10.0.1.0/24` | no |
| `databricks_private_subnet_cidr` | CIDR of the Databricks container (private) subnet. | `string` | `10.0.2.0/24` | no |
| `private_endpoint_subnet_cidr` | CIDR of the subnet hosting private endpoints. | `string` | `10.0.3.0/24` | no |
| `service_endpoints` | Service endpoints enabled on the Databricks subnets. Lets storage and Key Vault firewalls allow the subnets without private endpoints. | `list(string)` | `[Microsoft.Storage, Microsoft.KeyVault]` | no |
| `enable_nat_gateway` | Create a NAT gateway for Databricks egress. Required for secure cluster connectivity (no public IP) when no firewall provides outbound access. | `bool` | `false` | no |
| `nat_gateway_name` | NAT gateway name. Required when enable_nat_gateway is true. | `string` | `null` | no |
| `nat_public_ip_name` | Public IP name for the NAT gateway. Required when enable_nat_gateway is true. | `string` | `null` | no |
| `private_dns_zones` | Private DNS zones to create and link to this VNet, for example privatelink.dfs.core.windows.net. In a hub-and-spoke estate these normally live in the hub; leave empty and pass hub zone IDs to the private-endpoints module instead. | `list(string)` | `[]` | no |
| `tags` | Tags applied to all networking resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `vnet_id` | Virtual network resource ID. |
| `vnet_name` | Virtual network name. |
| `databricks_public_subnet_name` | Name of the Databricks host subnet. |
| `databricks_private_subnet_name` | Name of the Databricks container subnet. |
| `databricks_public_subnet_id` | ID of the Databricks host subnet. |
| `databricks_private_subnet_id` | ID of the Databricks container subnet. |
| `databricks_public_subnet_nsg_association_id` | NSG association ID for the host subnet (required by the Databricks workspace). |
| `databricks_private_subnet_nsg_association_id` | NSG association ID for the container subnet (required by the Databricks workspace). |
| `private_endpoint_subnet_id` | ID of the private endpoint subnet. |
| `nsg_id` | ID of the Databricks network security group. |
| `nat_gateway_public_ip` | Egress IP of the NAT gateway, or null when not enabled. Allow-list this on downstream firewalls. |
| `private_dns_zone_ids` | Map of private DNS zone name to zone ID for zones created by this module. |
