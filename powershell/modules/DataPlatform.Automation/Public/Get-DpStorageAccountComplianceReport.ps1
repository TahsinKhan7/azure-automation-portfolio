function Get-DpStorageAccountComplianceReport {
    <#
    .SYNOPSIS
        Audits every storage account in the current (or given) subscription.
    .EXAMPLE
        Get-DpStorageAccountComplianceReport -RequireSharedKeyDisabled | Where-Object { -not $_.IsCompliant }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param (
        [string]$SubscriptionId,

        [switch]$RequireSharedKeyDisabled,

        [string[]]$RequiredTag = @()
    )

    if ($SubscriptionId) {
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    }

    $report = foreach ($account in @(Get-AzStorageAccount)) {
        $result = Test-DpStorageAccountCompliance -StorageAccount $account -RequireSharedKeyDisabled:$RequireSharedKeyDisabled -RequiredTag $RequiredTag

        [pscustomobject]@{
            Name             = $result.Name
            ResourceGroup    = $result.ResourceGroup
            Location         = $account.PrimaryLocation
            Kind             = $account.Kind
            Sku              = $account.Sku.Name
            HnsEnabled       = $account.EnableHierarchicalNamespace
            MinTlsVersion    = $account.MinimumTlsVersion
            NetworkDefault   = $account.NetworkRuleSet.DefaultAction
            BlobPublicAccess = $account.AllowBlobPublicAccess
            SharedKeyAccess  = $account.AllowSharedKeyAccess
            IsCompliant      = $result.IsCompliant
            Findings         = ($result.Findings -join '; ')
        }
    }

    return @($report)
}
