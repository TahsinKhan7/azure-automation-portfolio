function Get-DpDatabricksToken {
    <#
    .SYNOPSIS
        Lists the personal access tokens visible to the calling identity.
    .EXAMPLE
        Get-DpDatabricksToken -WorkspaceUrl $url -AccessToken $token
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param (
        [Parameter(Mandatory)]
        [string]$WorkspaceUrl,

        [Parameter(Mandatory)]
        [securestring]$AccessToken
    )

    $response = Invoke-DpDatabricksApi -WorkspaceUrl $WorkspaceUrl -AccessToken $AccessToken -Path '/api/2.0/token/list'
    return @($response.token_infos)
}
