function Get-DpCostSummaryByResourceGroup {
    <#
    .SYNOPSIS
        Rolls per-resource cost rows up to subscription, month and resource group.
    .EXAMPLE
        Get-DpCostSummaryByResourceGroup -CostRow $perResourceRows
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$CostRow
    )

    $rollup = foreach ($group in ($CostRow | Group-Object -Property Subscription, Month, ResourceGroup)) {
        $first = $group.Group[0]

        [pscustomobject]@{
            Subscription  = $first.Subscription
            Month         = $first.Month
            ResourceGroup = $first.ResourceGroup
            TotalSpend    = [math]::Round([double]($group.Group | Measure-Object -Property TotalCost -Sum).Sum, 2)
            ResourceCount = $group.Count
        }
    }

    return @($rollup | Sort-Object -Property TotalSpend -Descending)
}
