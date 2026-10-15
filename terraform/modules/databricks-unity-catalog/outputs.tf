output "catalog_name" {
  description = "Name of the catalog."
  value       = databricks_catalog.this.name
}

output "schema_names" {
  description = "Fully qualified schema names (catalog.schema)."
  value       = [for s in databricks_schema.this : "${s.catalog_name}.${s.name}"]
}

output "storage_credential_name" {
  description = "Name of the storage credential."
  value       = databricks_storage_credential.lake.name
}

output "external_location_urls" {
  description = "Map of external location name to abfss:// URL."
  value       = { for k, v in databricks_external_location.this : v.name => v.url }
}
