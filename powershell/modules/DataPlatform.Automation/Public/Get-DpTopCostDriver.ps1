function Get-DpTopCostDriver {
    <#
    .SYNOPSIS
        Returns the N most expensive rows from a cost summary.
    .EXAMPLE
        Get-DpTopCostDriver -CostRow $perResourceRows -Top 10
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$CostRow,

        [ValidateRange(1, 1000)]
        [int]$Top = 10
    )

    return @($CostRow | Sort-Object -Property TotalCost -Descending | Select-Object -First $Top)
}
