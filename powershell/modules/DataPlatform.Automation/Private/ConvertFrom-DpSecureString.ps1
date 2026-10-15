function ConvertFrom-DpSecureString {
    <#
    .SYNOPSIS
        Returns the plain-text value of a SecureString for use in an HTTP header.
    .NOTES
        Uses NetworkCredential rather than Marshal so that no unmanaged memory
        is left to free. Call sites must not log or persist the result.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [securestring]$SecureString
    )

    return [System.Net.NetworkCredential]::new([string]::Empty, $SecureString).Password
}
