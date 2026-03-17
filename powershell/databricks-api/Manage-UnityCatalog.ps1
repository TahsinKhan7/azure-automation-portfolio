<#
.SYNOPSIS
    Manages Databricks Unity Catalog objects via the REST API.
.DESCRIPTION
    Creates and configures catalogs, schemas and external locations in Unity Catalog.
    Supports setting up medallion architecture (bronze/silver/gold schemas) and
    granting appropriate permissions.
.EXAMPLE
    .\Manage-UnityCatalog.ps1 -WorkspaceUrl "https://adb-xxx.azuredatabricks.net" -Action "Setup"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$WorkspaceUrl,
    [Parameter(Mandatory = $false)][string]$TokenSecretName = "dbx-token-prod",
    [Parameter(Mandatory = $false)][string]$KeyVaultName = "kv-prod-001",
    [ValidateSet("Setup", "Audit", "GrantPermissions")][string]$Action = "Audit"
)

$ErrorActionPreference = "Stop"
$token = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $TokenSecretName -AsPlainText
$headers = @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" }

function Invoke-DatabricksAPI {
    param ([string]$Endpoint, [string]$Method = "GET", [object]$Body)
    $uri = "$WorkspaceUrl/api/2.1/unity-catalog$Endpoint"
    $params = @{ Uri = $uri; Method = $Method; Headers = $headers }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 5) }
    Invoke-RestMethod @params
}

Write-Host "`n=== Unity Catalog Manager ===" -ForegroundColor Cyan

switch ($Action) {
    "Audit" {
        # List catalogs
        $catalogs = (Invoke-DatabricksAPI -Endpoint "/catalogs").catalogs
        Write-Host "`nCatalogs:" -ForegroundColor Cyan
        foreach ($cat in $catalogs) {
            Write-Host "  $($cat.name) | Owner: $($cat.owner)"
            
            # List schemas in each catalog
            $schemas = (Invoke-DatabricksAPI -Endpoint "/schemas?catalog_name=$($cat.name)").schemas
            foreach ($schema in $schemas) {
                Write-Host "    Schema: $($schema.name)" -ForegroundColor DarkGray
            }
        }
    }

    "Setup" {
        $catalogName = "enterprise_data"
        
        # Create catalog
        try {
            Invoke-DatabricksAPI -Endpoint "/catalogs" -Method POST -Body @{
                name    = $catalogName
                comment = "Enterprise data catalog - medallion architecture"
            }
            Write-Host "  Created catalog: $catalogName" -ForegroundColor Green
        }
        catch { Write-Host "  Catalog exists: $catalogName" -ForegroundColor Gray }

        # Create medallion schemas
        foreach ($layer in @("bronze", "silver", "gold")) {
            try {
                Invoke-DatabricksAPI -Endpoint "/schemas" -Method POST -Body @{
                    name         = $layer
                    catalog_name = $catalogName
                    comment      = "$layer layer - medallion architecture"
                }
                Write-Host "  Created schema: $catalogName.$layer" -ForegroundColor Green
            }
            catch { Write-Host "  Schema exists: $catalogName.$layer" -ForegroundColor Gray }
        }
    }

    "GrantPermissions" {
        $catalogName = "enterprise_data"
        
        $grants = @(
            @{ principal = "data-engineers"; privileges = @("USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY", "CREATE_TABLE") },
            @{ principal = "data-analysts";  privileges = @("USE_CATALOG", "USE_SCHEMA", "SELECT") },
            @{ principal = "data-scientists"; privileges = @("USE_CATALOG", "USE_SCHEMA", "SELECT", "CREATE_TABLE") }
        )

        foreach ($grant in $grants) {
            $body = @{
                changes = @(@{
                    principal  = $grant.principal
                    add        = $grant.privileges
                })
            }
            Invoke-DatabricksAPI -Endpoint "/permissions/catalog/$catalogName" -Method PATCH -Body $body
            Write-Host "  Granted: $($grant.principal) -> $($grant.privileges -join ', ')" -ForegroundColor Green
        }
    }
}
