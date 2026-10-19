function Invoke-DpDatabricksApi {
    <#
    .SYNOPSIS
        Calls a Databricks REST API endpoint with a bearer token.
    .DESCRIPTION
        Single call site for every Databricks request in the module and the
        scripts, so authentication, serialisation depth and error handling live
        in one place and tests can mock Invoke-RestMethod.
    .EXAMPLE
        Invoke-DpDatabricksApi -WorkspaceUrl $url -AccessToken $token -Path '/api/2.1/jobs/list'
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^https://')]
        [string]$WorkspaceUrl,

        [Parameter(Mandatory)]
        [securestring]$AccessToken,

        [Parameter(Mandatory)]
        [ValidatePattern('^/')]
        [string]$Path,

        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string]$Method = 'GET',

        [object]$Body
    )

    $request = @{
        Uri     = "$($WorkspaceUrl.TrimEnd('/'))$Path"
        Method  = $Method
        Headers = Get-DpBearerHeader -AccessToken $AccessToken
    }

    if ($null -ne $Body) {
        $request['Body'] = ($Body | ConvertTo-Json -Depth 10)
    }

    return Invoke-RestMethod @request
}
