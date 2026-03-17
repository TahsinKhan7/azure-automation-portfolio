<#
.SYNOPSIS
    Generates Azure cost breakdown reports by subscription, resource group and resource type.

.DESCRIPTION
    Queries Azure Cost Management APIs to produce a spend summary for the current and
    previous billing periods. Highlights top cost drivers and month-over-month changes
    to support FinOps reviews and cost optimisation efforts.

.PARAMETER SubscriptionIds
    Array of subscription IDs to report on. Default: current subscription.

.PARAMETER BillingPeriodMonths
    Number of months to include. Default: 2 (current + previous).

.PARAMETER OutputPath
    Path for report output.

.EXAMPLE
    .\Get-AzureCostReport.ps1 -SubscriptionIds @("sub-id-1","sub-id-2") -OutputPath ".\reports\"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string[]]$SubscriptionIds,

    [Parameter(Mandatory = $false)]
    [int]$BillingPeriodMonths = 2,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\reports"
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== Azure Cost Report ===" -ForegroundColor Cyan

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Default to current subscription if none specified
if (-not $SubscriptionIds) {
    $SubscriptionIds = @((Get-AzContext).Subscription.Id)
}

$allCosts = @()

foreach ($subId in $SubscriptionIds) {
    Write-Host "`nSubscription: $subId" -ForegroundColor Cyan
    Set-AzContext -SubscriptionId $subId | Out-Null

    $subName = (Get-AzSubscription -SubscriptionId $subId).Name

    # Query cost data for each month
    for ($i = 0; $i -lt $BillingPeriodMonths; $i++) {
        $startDate = (Get-Date).AddMonths(-$i).ToString("yyyy-MM-01")
        $endDate = (Get-Date $startDate).AddMonths(1).AddDays(-1).ToString("yyyy-MM-dd")
        $monthLabel = (Get-Date $startDate).ToString("yyyy-MM")

        Write-Host "  Querying: $monthLabel" -ForegroundColor DarkGray

        try {
            $costs = Get-AzConsumptionUsageDetail -StartDate $startDate -EndDate $endDate `
                        -ErrorAction SilentlyContinue

            if ($costs) {
                $grouped = $costs | Group-Object -Property InstanceName | ForEach-Object {
                    [PSCustomObject]@{
                        Subscription   = $subName
                        Month          = $monthLabel
                        ResourceGroup  = ($_.Group[0].InstanceId -split '/')[4]
                        ResourceName   = $_.Name
                        ResourceType   = $_.Group[0].ConsumedService
                        TotalCost      = [math]::Round(($_.Group | Measure-Object -Property PretaxCost -Sum).Sum, 2)
                        Currency       = $_.Group[0].Currency
                    }
                }
                $allCosts += $grouped
            }
        }
        catch {
            Write-Warning "  Failed to query costs for $monthLabel : $_"
        }
    }
}

# Generate summary by resource group
$rgSummary = $allCosts | Group-Object Subscription, Month, ResourceGroup | ForEach-Object {
    [PSCustomObject]@{
        Subscription  = ($_.Group[0].Subscription)
        Month         = ($_.Group[0].Month)
        ResourceGroup = ($_.Group[0].ResourceGroup)
        TotalSpend    = [math]::Round(($_.Group | Measure-Object -Property TotalCost -Sum).Sum, 2)
        ResourceCount = $_.Count
    }
} | Sort-Object -Property TotalSpend -Descending

# Export detailed report
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$detailFile = Join-Path $OutputPath "cost-detail-$timestamp.csv"
$summaryFile = Join-Path $OutputPath "cost-summary-$timestamp.csv"

$allCosts | Export-Csv -Path $detailFile -NoTypeInformation
$rgSummary | Export-Csv -Path $summaryFile -NoTypeInformation

# Print top cost drivers
Write-Host "`n=== Top 10 Cost Drivers ===" -ForegroundColor Cyan
$allCosts | Sort-Object TotalCost -Descending | Select-Object -First 10 |
    Format-Table Subscription, Month, ResourceGroup, ResourceName, TotalCost, Currency -AutoSize

Write-Host "`n=== Monthly Spend by Resource Group ===" -ForegroundColor Cyan
$rgSummary | Select-Object -First 15 |
    Format-Table Subscription, Month, ResourceGroup, TotalSpend, ResourceCount -AutoSize

Write-Host "Detailed report: $detailFile" -ForegroundColor Green
Write-Host "Summary report:  $summaryFile" -ForegroundColor Green
