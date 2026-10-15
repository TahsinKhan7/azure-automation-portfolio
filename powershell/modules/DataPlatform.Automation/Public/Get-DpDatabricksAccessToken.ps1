function Get-DpDatabricksAccessToken {
    <#
    .SYNOPSIS
        Retrieves a Databricks access token from Key Vault as a SecureString.
    .EXAMPLE
        $token = Get-DpDatabricksAccessToken -KeyVaultName kv-dp-data-prod-01 -SecretName dbx-token-prod
    #>
    [CmdletBinding()]
    [OutputType([securestring])]
    param (
        [Parameter(Mandatory)]
        [string]$KeyVaultName,

        [Parameter(Mandatory)]
        [string]$SecretName
    )

    $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName
    if ($null -eq $secret -or $null -eq $secret.SecretValue) {
        throw "Secret '$SecretName' was not found in Key Vault '$KeyVaultName' or has no value."
    }

    return $secret.SecretValue
}
