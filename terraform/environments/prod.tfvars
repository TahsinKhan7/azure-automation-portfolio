environment    = "prod"
location       = "uksouth"
workspace_name = "dbx-prod-001"
storage_name   = "stproddatalake001"
key_vault_name = "kv-prod-001"
vnet_name      = "vnet-prod-001"
no_public_ip   = true
tags           = { Environment = "prod", CostCentre = "CC-PROD" }
