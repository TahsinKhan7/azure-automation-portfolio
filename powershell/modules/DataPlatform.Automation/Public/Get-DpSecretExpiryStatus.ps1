function Get-DpSecretExpiryStatus {
    <#
    .SYNOPSIS
        Classifies a secret's expiry date as Valid, Expiring Soon, Expired or No Expiry Set.
    .EXAMPLE
        Get-DpSecretExpiryStatus -Expires (Get-Date).AddDays(10) -WarningDays 30
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [nullable[datetime]]$Expires,

        [ValidateRange(1, 365)]
        [int]$WarningDays = 30,

        [datetime]$Now = (Get-Date)
    )

    if ($null -eq $Expires) {
        return [pscustomobject]@{ Status = 'No Expiry Set'; DaysUntilExpiry = $null }
    }

    $days = [math]::Floor(([datetime]$Expires - $Now).TotalDays)

    $status = if ($days -lt 0) { 'Expired' }
    elseif ($days -le $WarningDays) { 'Expiring Soon' }
    else { 'Valid' }

    return [pscustomobject]@{ Status = $status; DaysUntilExpiry = [int]$days }
}
