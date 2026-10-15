<#
.SYNOPSIS
    Generates Azure cost breakdown reports by subscription, resource group and resource.

.DESCRIPTION
    Queries Cost Management usage detail for the current and previous billing
    periods, aggregates it with the DataPlatform.Automation module and writes
    detail and summary CSVs. Highlights the top cost drivers for FinOps reviews.

.PARAMETER SubscriptionId
    Subscription IDs to report on. Defaults to the current context subscription.

.PARAMETER BillingPeriodMonths
    Number of months to include, counting back from the current month.

.PARAMETER OutputPath
    Folder for the CSV output.

.EXAMPLE
    ./Get-AzureCostReport.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -OutputPath ./reports
#>
#Requires -Version 7.0
[CmdletBinding()]
param (
    [string[]]$SubscriptionId,

    [ValidateRange(1, 12)]
    [int]$BillingPeriodMonths = 2,

    [string]$OutputPath = './reports'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'modules/DataPlatform.Automation/DataPlatform.Automation.psd1') -Force

Write-DpLog -Message 'Azure cost report'

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

if (-not $SubscriptionId) {
    $SubscriptionId = @((Get-AzContext).Subscription.Id)
}

$allCosts = [System.Collections.Generic.List[object]]::new()

foreach ($id in $SubscriptionId) {
    Set-AzContext -SubscriptionId $id | Out-Null
    $subscriptionName = (Get-AzSubscription -SubscriptionId $id).Name
    Write-DpLog -Message "Subscription: $subscriptionName"

    for ($i = 0; $i -lt $BillingPeriodMonths; $i++) {
        $monthStart = (Get-Date -Day 1).Date.AddMonths(-$i)
        $monthEnd = $monthStart.AddMonths(1).AddDays(-1)
        $monthLabel = $monthStart.ToString('yyyy-MM')
        Write-DpLog -Message "  Querying $monthLabel" -Level Debug

        try {
            $usage = @(Get-AzConsumptionUsageDetail -StartDate $monthStart -EndDate $monthEnd)
            if ($usage.Count -gt 0) {
                $allCosts.AddRange([object[]](ConvertTo-DpCostSummary -UsageDetail $usage -SubscriptionName $subscriptionName -Month $monthLabel))
            }
        } catch {
            Write-DpLog -Message "Failed to query costs for $monthLabel in $subscriptionName : $($_.Exception.Message)" -Level Warning
        }
    }
}

$resourceGroupSummary = Get-DpCostSummaryByResourceGroup -CostRow $allCosts
$topDrivers = Get-DpTopCostDriver -CostRow $allCosts -Top 10

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$detailFile = Join-Path -Path $OutputPath -ChildPath "cost-detail-$timestamp.csv"
$summaryFile = Join-Path -Path $OutputPath -ChildPath "cost-summary-$timestamp.csv"
$allCosts | Export-Csv -Path $detailFile -NoTypeInformation
$resourceGroupSummary | Export-Csv -Path $summaryFile -NoTypeInformation

Write-DpLog -Message 'Top 10 cost drivers'
$topDrivers | Format-Table -Property Subscription, Month, ResourceGroup, ResourceName, TotalCost, Currency -AutoSize | Out-String | Write-DpLog

Write-DpLog -Message "Detailed report: $detailFile" -Level Success
Write-DpLog -Message "Summary report:  $summaryFile" -Level Success

[pscustomobject]@{
    DetailFile  = $detailFile
    SummaryFile = $summaryFile
    Rows        = $allCosts.Count
}
