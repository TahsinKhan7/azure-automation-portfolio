function Get-DpTokenRotationPlan {
    <#
    .SYNOPSIS
        Decides which Databricks tokens to rotate, keep or treat as expired.
    .DESCRIPTION
        Takes the token_infos objects from the Databricks token list API
        (token_id, comment, creation_time and expiry_time in epoch milliseconds,
        -1 for no expiry) and classifies each one relative to a rotation window.
        The reference time is a parameter so the logic is deterministic in tests.
    .EXAMPLE
        Get-DpTokenRotationPlan -Token $tokens -RotationWindowDays 7 | Where-Object Action -eq 'Rotate'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Token,

        [ValidateRange(1, 365)]
        [int]$RotationWindowDays = 7,

        [datetime]$Now = (Get-Date).ToUniversalTime(),

        [switch]$IncludeNonExpiring
    )

    $plan = foreach ($item in $Token) {
        $expiryMs = [long]$item.expiry_time
        $neverExpires = $expiryMs -le 0

        $expiresAt = if ($neverExpires) { $null } else { [DateTimeOffset]::FromUnixTimeMilliseconds($expiryMs).UtcDateTime }
        $createdAt = if ($item.creation_time) { [DateTimeOffset]::FromUnixTimeMilliseconds([long]$item.creation_time).UtcDateTime } else { $null }
        $daysRemaining = if ($neverExpires) { $null } else { [math]::Floor(($expiresAt - $Now.ToUniversalTime()).TotalDays) }

        $action = if ($neverExpires) {
            if ($IncludeNonExpiring) { 'Rotate' } else { 'Keep' }
        } elseif ($daysRemaining -lt 0) {
            'Expired'
        } elseif ($daysRemaining -le $RotationWindowDays) {
            'Rotate'
        } else {
            'Keep'
        }

        [pscustomobject]@{
            TokenId       = [string]$item.token_id
            Comment       = [string]$item.comment
            CreatedAt     = $createdAt
            ExpiresAt     = $expiresAt
            DaysRemaining = $daysRemaining
            Action        = $action
        }
    }

    return @($plan)
}
