function Invoke-DpAdoApi {
    <#
    .SYNOPSIS
        Thin wrapper around Invoke-RestMethod for the Azure DevOps REST API.
    .NOTES
        Kept separate so that tests can mock a single call site.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [uri]$Uri,

        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$Method = 'GET',

        [Parameter(Mandatory)]
        [hashtable]$Headers,

        [object]$Body
    )

    $request = @{
        Uri     = $Uri
        Method  = $Method
        Headers = $Headers
    }

    if ($null -ne $Body) {
        $request['Body'] = ($Body | ConvertTo-Json -Depth 10)
    }

    return Invoke-RestMethod @request
}
