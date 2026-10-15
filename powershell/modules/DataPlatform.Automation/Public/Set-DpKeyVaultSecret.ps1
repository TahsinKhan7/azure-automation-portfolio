function Set-DpKeyVaultSecret {
    <#
    .SYNOPSIS
        Writes a secret to Key Vault with content type and optional expiry.
    .EXAMPLE
        Set-DpKeyVaultSecret -VaultName kv-dp-data-prod-01 -Name dbx-token-prod -SecretValue $secure -ExpiresOn (Get-Date).AddDays(30)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string]$VaultName,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [securestring]$SecretValue,

        [string]$ContentType = 'text/plain',

        [nullable[datetime]]$ExpiresOn
    )

    if (-not $PSCmdlet.ShouldProcess("$VaultName/$Name", 'Set secret value')) {
        return
    }

    $parameters = @{
        VaultName   = $VaultName
        Name        = $Name
        SecretValue = $SecretValue
        ContentType = $ContentType
    }

    if ($null -ne $ExpiresOn) {
        $parameters['Expires'] = ([datetime]$ExpiresOn).ToUniversalTime()
    }

    Set-AzKeyVaultSecret @parameters | Out-Null
}
