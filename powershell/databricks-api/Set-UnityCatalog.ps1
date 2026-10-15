<#
.SYNOPSIS
    Audits or configures Unity Catalog objects (catalog, medallion schemas, grants) through the REST API.

.DESCRIPTION
    Formerly Manage-UnityCatalog.ps1; renamed because Manage is not an approved
    verb. The Terraform module databricks-unity-catalog is the primary way to
    manage these objects; this script supports audits and ad-hoc bootstraps.

.EXAMPLE
    ./Set-UnityCatalog.ps1 -WorkspaceUrl https://adb-0000000000000000.0.azuredatabricks.net -KeyVaultName kv-dp-data-dev-01 -TokenSecretName dbx-token-dev -Action Audit
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [ValidatePattern('^https://')]
    [string]$WorkspaceUrl,

    [Parameter(Mandatory)]
    [string]$KeyVaultName,

    [Parameter(Mandatory)]
    [string]$TokenSecretName,

    [ValidateSet('Audit', 'Setup', 'GrantPermissions')]
    [string]$Action = 'Audit',

    [ValidatePattern('^[a-z][a-z0-9_]{1,62}$')]
    [string]$CatalogName = 'dp_data_dev',

    [string[]]$Schema = @('bronze', 'silver', 'gold'),

    # Group name => privileges. Defaults to the engineer/analyst split below.
    [hashtable]$Grant
)

$ErrorActionPreference = 'Stop'
if (-not $PSBoundParameters.ContainsKey('Grant')) {
    $Grant = @{
        'data-engineers' = @('USE_CATALOG', 'USE_SCHEMA', 'SELECT', 'MODIFY', 'CREATE_TABLE')
        'data-analysts'  = @('USE_CATALOG', 'USE_SCHEMA', 'SELECT')
    }
}
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../modules/DataPlatform.Automation/DataPlatform.Automation.psd1') -Force

$token = Get-DpDatabricksAccessToken -KeyVaultName $KeyVaultName -SecretName $TokenSecretName
$ucPath = '/api/2.1/unity-catalog'
Write-DpLog -Message "Unity Catalog: $Action"

switch ($Action) {
    'Audit' {
        foreach ($catalog in @((Invoke-DpDatabricksApi -WorkspaceUrl $WorkspaceUrl -AccessToken $token -Path "$ucPath/catalogs").catalogs)) {
            $schemas = @((Invoke-DpDatabricksApi -WorkspaceUrl $WorkspaceUrl -AccessToken $token -Path "$ucPath/schemas?catalog_name=$($catalog.name)").schemas)
            [pscustomobject]@{
                Catalog   = $catalog.name
                Owner     = $catalog.owner
                Isolation = $catalog.isolation_mode
                Schemas   = ($schemas.name -join ', ')
            }
        }
    }
    'Setup' {
        if ($PSCmdlet.ShouldProcess($WorkspaceUrl, "Create catalog $CatalogName")) {
            try {
                Invoke-DpDatabricksApi -WorkspaceUrl $WorkspaceUrl -AccessToken $token -Path "$ucPath/catalogs" -Method POST -Body @{ name = $CatalogName; comment = 'Lakehouse catalog (medallion architecture)' } | Out-Null
                Write-DpLog -Message "Created catalog $CatalogName" -Level Success
            } catch {
                Write-DpLog -Message "Catalog $CatalogName already exists or could not be created: $($_.Exception.Message)" -Level Debug
            }
        }
        foreach ($name in $Schema) {
            if ($PSCmdlet.ShouldProcess($WorkspaceUrl, "Create schema $CatalogName.$name")) {
                try {
                    Invoke-DpDatabricksApi -WorkspaceUrl $WorkspaceUrl -AccessToken $token -Path "$ucPath/schemas" -Method POST -Body @{ name = $name; catalog_name = $CatalogName; comment = "$name layer" } | Out-Null
                    Write-DpLog -Message "Created schema $CatalogName.$name" -Level Success
                } catch {
                    Write-DpLog -Message "Schema $CatalogName.$name already exists or could not be created: $($_.Exception.Message)" -Level Debug
                }
            }
        }
    }
    'GrantPermissions' {
        foreach ($principal in $Grant.Keys) {
            if ($PSCmdlet.ShouldProcess("$CatalogName", "Grant $($Grant[$principal] -join ', ') to $principal")) {
                $body = @{ changes = @(@{ principal = $principal; add = @($Grant[$principal]) }) }
                Invoke-DpDatabricksApi -WorkspaceUrl $WorkspaceUrl -AccessToken $token -Path "$ucPath/permissions/catalog/$CatalogName" -Method PATCH -Body $body | Out-Null
                Write-DpLog -Message "Granted $principal -> $($Grant[$principal] -join ', ')" -Level Success
            }
        }
    }
}
