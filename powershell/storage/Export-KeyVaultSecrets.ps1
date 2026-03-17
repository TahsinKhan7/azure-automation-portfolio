<#
.SYNOPSIS
    Exports Key Vault secret metadata for compliance auditing and expiry tracking.

.DESCRIPTION
    Scans one or more Azure Key Vaults and generates a report of all secrets including
    their creation date, expiry date, enabled status and days until expiry.
    Does NOT export secret values — only metadata for compliance purposes.

.PARAMETER VaultNames
    Array of Key Vault names to audit.

.PARAMETER OutputPath
    Path for the CSV report output.

.PARAMETER ExpiryWarningDays
    Flag secrets expiring within this many days. Default: 30.

.EXAMPLE
    .\Export-KeyVaultSecrets.ps1 -VaultNames @("kv-prod-001","kv-prod-002") -OutputPath ".\reports\"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string[]]$VaultNames,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\reports",

    [Parameter(Mandatory = $false)]
    [int]$ExpiryWarningDays = 30
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== Key Vault Secret Audit ===" -ForegroundColor Cyan

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$allSecrets = @()
$expiringCount = 0

foreach ($vaultName in $VaultNames) {
    Write-Host "`nScanning: $vaultName" -ForegroundColor Cyan

    try {
        $secrets = Get-AzKeyVaultSecret -VaultName $vaultName

        foreach ($secret in $secrets) {
            $detail = Get-AzKeyVaultSecret -VaultName $vaultName -Name $secret.Name

            $daysUntilExpiry = $null
            $expiryStatus = "No Expiry Set"

            if ($detail.Expires) {
                $daysUntilExpiry = ($detail.Expires - (Get-Date)).Days

                if ($daysUntilExpiry -lt 0) {
                    $expiryStatus = "EXPIRED"
                }
                elseif ($daysUntilExpiry -le $ExpiryWarningDays) {
                    $expiryStatus = "EXPIRING SOON"
                    $expiringCount++
                }
                else {
                    $expiryStatus = "Valid"
                }
            }

            $allSecrets += [PSCustomObject]@{
                VaultName       = $vaultName
                SecretName      = $secret.Name
                Enabled         = $detail.Enabled
                Created         = $detail.Created
                Updated         = $detail.Updated
                Expires         = $detail.Expires
                DaysUntilExpiry = $daysUntilExpiry
                ExpiryStatus    = $expiryStatus
                ContentType     = $detail.ContentType
            }
        }

        Write-Host "  Found $($secrets.Count) secret(s)" -ForegroundColor Green
    }
    catch {
        Write-Warning "  Failed to scan $vaultName : $_"
    }
}

# Export to CSV
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportFile = Join-Path $OutputPath "keyvault-audit-$timestamp.csv"
$allSecrets | Export-Csv -Path $reportFile -NoTypeInformation
Write-Host "`nReport saved: $reportFile" -ForegroundColor Green

# Print summary
Write-Host "`n=== Audit Summary ===" -ForegroundColor Cyan
Write-Host "Vaults scanned:   $($VaultNames.Count)"
Write-Host "Total secrets:    $($allSecrets.Count)"
Write-Host "Expiring soon:    $expiringCount (within $ExpiryWarningDays days)"
Write-Host "Expired:          $(($allSecrets | Where-Object { $_.ExpiryStatus -eq 'EXPIRED' }).Count)"
Write-Host "No expiry set:    $(($allSecrets | Where-Object { $_.ExpiryStatus -eq 'No Expiry Set' }).Count)"

if ($expiringCount -gt 0) {
    Write-Host "`nSecrets expiring soon:" -ForegroundColor Yellow
    $allSecrets | Where-Object { $_.ExpiryStatus -eq "EXPIRING SOON" } |
        Format-Table VaultName, SecretName, Expires, DaysUntilExpiry -AutoSize
}
