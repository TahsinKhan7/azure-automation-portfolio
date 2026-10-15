function Revoke-DpDatabricksToken {
    <#
    .SYNOPSIS
        Revokes a Databricks personal access token by ID.
    .EXAMPLE
        Revoke-DpDatabricksToken -WorkspaceUrl $url -AccessToken $token -TokenId $old.TokenId
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory)]
        [string]$WorkspaceUrl,

        [Parameter(Mandatory)]
        [securestring]$AccessToken,

        [Parameter(Mandatory)]
        [string]$TokenId
    )

    if ($PSCmdlet.ShouldProcess($WorkspaceUrl, "Revoke token $TokenId")) {
        Invoke-DpDatabricksApi -WorkspaceUrl $WorkspaceUrl -AccessToken $AccessToken -Path '/api/2.0/token/delete' -Method POST -Body @{ token_id = $TokenId } | Out-Null
    }
}
