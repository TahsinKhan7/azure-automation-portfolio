output "id" {
  description = "Key Vault resource ID."
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "Key Vault name."
  value       = azurerm_key_vault.this.name
}

output "vault_uri" {
  description = "Vault URI, for example https://kv-dp-data-dev-01.vault.azure.net/."
  value       = azurerm_key_vault.this.vault_uri
}

output "tenant_id" {
  description = "Tenant the vault belongs to."
  value       = azurerm_key_vault.this.tenant_id
}
