<#
.SYNOPSIS
    Audits storage accounts against the platform security baseline and exports the findings.

.DESCRIPTION
    The baseline (HTTPS only, TLS 1.2, no anonymous access, firewall Deny,
    optionally Shared Key disabled) is implemented in
    Test-DpStorageAccountCompliance and is unit tested.

.EXAMPLE
    ./Get-StorageAccountAudit.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -RequireSharedKeyDisabled
#>
#Requires -Version 7.0
[CmdletBinding()]
param (
    [string]$SubscriptionId,

    [string]$OutputPath = './reports',

    [switch]$RequireSharedKeyDisabled,

    [string[]]$RequiredTag = @('Environment', 'CostCentre')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../modules/DataPlatform.Automation/DataPlatform.Automation.psd1') -Force

Write-DpLog -Message 'Storage account compliance audit'

$report = Get-DpStorageAccountComplianceReport -SubscriptionId $SubscriptionId -RequireSharedKeyDisabled:$RequireSharedKeyDisabled -RequiredTag $RequiredTag
$nonCompliant = @($report | Where-Object { -not $_.IsCompliant })

Write-DpLog -Message "Accounts: $($report.Count) | Compliant: $($report.Count - $nonCompliant.Count) | Non-compliant: $($nonCompliant.Count)"
foreach ($account in $nonCompliant) {
    Write-DpLog -Message "  $($account.Name): $($account.Findings)" -Level Warning
}

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}
$file = Join-Path -Path $OutputPath -ChildPath "storage-audit-$(Get-Date -Format 'yyyyMMdd').csv"
$report | Export-Csv -Path $file -NoTypeInformation
Write-DpLog -Message "Report saved: $file" -Level Success

$report
