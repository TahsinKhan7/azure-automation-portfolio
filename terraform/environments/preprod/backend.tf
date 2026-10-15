# Remote state: one storage account for the platform, one blob per environment.
# The storage account name is a placeholder; the real value is injected by the
# pipeline with -backend-config so that no environment can be pointed at the
# wrong state by editing this file.
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-dp-tfstate-uks-01"
    storage_account_name = "stdptfstateuks01"
    container_name       = "tfstate"
    key                  = "dataplatform/preprod.tfstate"
    use_oidc             = true
    use_azuread_auth     = true
  }
}
