function New-DpDatabricksToken {
    <#
    .SYNOPSIS
        Creates a new Databricks personal access token and returns its value as a SecureString.
    .EXAMPLE
        $new = New-DpDatabricksToken -WorkspaceUrl $url -AccessToken $token -LifetimeDays 30 -Comment 'rotation 2026-10-15'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [string]$WorkspaceUrl,

        [Parameter(Mandatory)]
        [securestring]$AccessToken,

        [ValidateRange(1, 730)]
        [int]$LifetimeDays = 30,

        [Parameter(Mandatory)]
        [string]$Comment
    )

    if (-not $PSCmdlet.ShouldProcess($WorkspaceUrl, "Create token '$Comment' valid for $LifetimeDays days")) {
        return $null
    }

    $body = @{
        lifetime_seconds = $LifetimeDays * 24 * 60 * 60
        comment          = $Comment
    }

    $response = Invoke-DpDatabricksApi -WorkspaceUrl $WorkspaceUrl -AccessToken $AccessToken -Path '/api/2.0/token/create' -Method POST -Body $body

    return [pscustomobject]@{
        TokenId    = $response.token_info.token_id
        ExpiresAt  = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$response.token_info.expiry_time).UtcDateTime
        TokenValue = ConvertTo-DpSecureString -Value $response.token_value
    }
}
