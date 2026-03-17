<#
.SYNOPSIS
    Audits and manages Azure Storage Accounts across subscriptions.
.DESCRIPTION
    Reports on storage account configurations including access tiers,
    replication, network rules, encryption and blob lifecycle policies.
    Identifies non-compliant accounts for remediation.
.EXAMPLE
    .\Get-StorageAccountAudit.ps1 -SubscriptionId "xxxx" -OutputPath ".\reports\"
#>

[CmdletBinding()]
param (
    [string]$SubscriptionId,
    [string]$OutputPath = ".\reports"
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== Storage Account Audit ===" -ForegroundColor Cyan

if ($SubscriptionId) { Set-AzContext -SubscriptionId $SubscriptionId | Out-Null }

$storageAccounts = Get-AzStorageAccount
$report = @()

foreach ($sa in $storageAccounts) {
    $networkRules = $sa.NetworkRuleSet

    $report += [PSCustomObject]@{
        Name              = $sa.StorageAccountName
        ResourceGroup     = $sa.ResourceGroupName
        Location          = $sa.PrimaryLocation
        Kind              = $sa.Kind
        Sku               = $sa.Sku.Name
        AccessTier        = $sa.AccessTier
        HttpsOnly         = $sa.EnableHttpsTrafficOnly
        MinTlsVersion     = $sa.MinimumTlsVersion
        HnsEnabled        = $sa.EnableHierarchicalNamespace
        BlobPublicAccess  = $sa.AllowBlobPublicAccess
        NetworkDefault    = $networkRules.DefaultAction
        VNetRules         = ($networkRules.VirtualNetworkRules | Measure-Object).Count
        IpRules           = ($networkRules.IpRules | Measure-Object).Count
        Compliant         = (
            $sa.EnableHttpsTrafficOnly -eq $true -and
            $sa.MinimumTlsVersion -eq "TLS1_2" -and
            $networkRules.DefaultAction -eq "Deny" -and
            $sa.AllowBlobPublicAccess -eq $false
        )
    }
}

# Display summary
$compliant = ($report | Where-Object { $_.Compliant }).Count
$nonCompliant = ($report | Where-Object { -not $_.Compliant }).Count

Write-Host "`nTotal accounts:   $($report.Count)"
Write-Host "Compliant:        $compliant" -ForegroundColor Green
Write-Host "Non-compliant:    $nonCompliant" -ForegroundColor $(if ($nonCompliant -gt 0) { "Red" } else { "Green" })

if ($nonCompliant -gt 0) {
    Write-Host "`nNon-compliant accounts:" -ForegroundColor Yellow
    $report | Where-Object { -not $_.Compliant } | Format-Table Name, MinTlsVersion, NetworkDefault, BlobPublicAccess -AutoSize
}

# Export
if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
$file = Join-Path $OutputPath "storage-audit-$(Get-Date -Format 'yyyyMMdd').csv"
$report | Export-Csv -Path $file -NoTypeInformation
Write-Host "`nReport saved: $file" -ForegroundColor Green
