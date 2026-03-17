# Terraform Modules

Reusable, modular Terraform configurations for provisioning Azure resources. Designed for multi-environment deployments (dev/prod per business unit) with governance and security compliance built in.

## Modules

| Module | Resources Created |
|--------|------------------|
| `modules/databricks-workspace/` | Databricks workspace, managed resource group, VNet injection config |
| `modules/storage-account/` | Storage account with ADLS Gen2, containers for medallion architecture (bronze/silver/gold) |
| `modules/key-vault/` | Key Vault with access policies, soft delete, purge protection |
| `modules/networking/` | VNet, subnets (public/private for Databricks), NSGs, security rules |

## Usage

```bash
# Initialise and plan for dev environment
terraform init
terraform plan -var-file="environments/dev.tfvars"

# Apply for production
terraform plan -var-file="environments/prod.tfvars"
terraform apply -var-file="environments/prod.tfvars"
```

## Requirements

- Terraform >= 1.5
- Azure Provider >= 3.0
- Authenticated Azure CLI session
