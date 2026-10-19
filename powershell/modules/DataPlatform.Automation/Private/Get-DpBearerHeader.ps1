function Get-DpBearerHeader {
    <#
    .SYNOPSIS
        Builds the Authorization and Content-Type headers for a bearer-token API.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)]
        [securestring]$AccessToken
    )

    return @{
        Authorization  = "Bearer $(ConvertFrom-DpSecureString -SecureString $AccessToken)"
        'Content-Type' = 'application/json'
    }
}
