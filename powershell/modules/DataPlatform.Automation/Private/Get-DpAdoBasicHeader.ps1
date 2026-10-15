function Get-DpAdoBasicHeader {
    <#
    .SYNOPSIS
        Builds the Basic authentication header Azure DevOps expects for a PAT.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)]
        [securestring]$AccessToken
    )

    $pat = ConvertFrom-DpSecureString -SecureString $AccessToken
    $encoded = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))

    return @{
        Authorization  = "Basic $encoded"
        'Content-Type' = 'application/json'
    }
}
