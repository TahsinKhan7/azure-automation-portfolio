function ConvertTo-DpCostSummary {
    <#
    .SYNOPSIS
        Aggregates Cost Management usage detail rows into one row per resource.
    .DESCRIPTION
        Accepts the objects returned by Get-AzConsumptionUsageDetail (or any
        objects with InstanceId, InstanceName, ConsumedService, PretaxCost and
        Currency) and sums cost per resource, deriving the resource group from
        the resource ID.
    .EXAMPLE
        $rows = Get-AzConsumptionUsageDetail -StartDate 2026-09-01 -EndDate 2026-09-30
        ConvertTo-DpCostSummary -UsageDetail $rows -SubscriptionName 'Data Platform' -Month '2026-09'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$UsageDetail,

        [Parameter(Mandatory)]
        [string]$SubscriptionName,

        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9]{4}-[0-9]{2}$')]
        [string]$Month
    )

    $summary = foreach ($group in ($UsageDetail | Group-Object -Property InstanceId)) {
        $first = $group.Group[0]
        $total = ($group.Group | Measure-Object -Property PretaxCost -Sum).Sum

        [pscustomobject]@{
            Subscription  = $SubscriptionName
            Month         = $Month
            ResourceGroup = Get-DpResourceGroupFromResourceId -ResourceId $group.Name
            ResourceName  = $first.InstanceName
            ResourceType  = $first.ConsumedService
            TotalCost     = [math]::Round([double]$total, 2)
            Currency      = $first.Currency
        }
    }

    return @($summary)
}
