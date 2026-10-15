function ConvertTo-DpSecureString {
    <#
    .SYNOPSIS
        Converts a plain-text value that has already been received in memory into a SecureString.
    .DESCRIPTION
        Used only for values that arrive in plain text from an external API
        (for example a newly created Databricks token) or from a pipeline
        environment variable, immediately before they are stored or sent.
        This is the single sanctioned call site for the conversion.
    .EXAMPLE
        $secure = ConvertTo-DpSecureString -Value $env:SYSTEM_ACCESSTOKEN
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'The value is already in memory in plain text (API response or pipeline variable); converting it here limits its lifetime rather than extending it.')]
    [CmdletBinding()]
    [OutputType([securestring])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrEmpty($Value)) {
        throw 'Cannot convert an empty value to a SecureString.'
    }

    return ConvertTo-SecureString -String $Value -AsPlainText -Force
}
