<#
.SYNOPSIS
    Exports Key Vault secret metadata (never values) with expiry classification.

.DESCRIPTION
    Produces the CSV that feeds the KeyVaultSecretInventory_CL table queried by
    kql-queries/key-vault-secret-near-expiry.kql. Classification logic lives in
    Get-DpSecretExpiryStatus and is unit tested.

.EXAMPLE
    ./Export-KeyVaultSecrets.ps1 -VaultName kv-dp-data-prod-01, kv-dp-data-preprod-01 -OutputPath ./reports
#>
#Requires -Version 7.0
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string[]]$VaultName,

    [string]$OutputPath = './reports',

    [ValidateRange(1, 365)]
    [int]$ExpiryWarningDays = 30
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../modules/DataPlatform.Automation/DataPlatform.Automation.psd1') -Force

Write-DpLog -Message 'Key Vault secret inventory'

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$inventory = foreach ($vault in $VaultName) {
    Write-DpLog -Message "Scanning $vault"
    try {
        Get-DpKeyVaultSecretInventory -VaultName $vault -WarningDays $ExpiryWarningDays
    } catch {
        Write-DpLog -Message "Failed to scan $vault : $($_.Exception.Message)" -Level Warning
    }
}
$inventory = @($inventory)

$reportFile = Join-Path -Path $OutputPath -ChildPath "keyvault-inventory-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$inventory | Export-Csv -Path $reportFile -NoTypeInformation
Write-DpLog -Message "Report saved: $reportFile" -Level Success

$byStatus = $inventory | Group-Object -Property ExpiryStatus -AsHashTable -AsString

[pscustomobject]@{
    ReportFile   = $reportFile
    Vaults       = $VaultName.Count
    Secrets      = $inventory.Count
    ExpiringSoon = @($byStatus['Expiring Soon']).Count
    Expired      = @($byStatus['Expired']).Count
    NoExpirySet  = @($byStatus['No Expiry Set']).Count
}
