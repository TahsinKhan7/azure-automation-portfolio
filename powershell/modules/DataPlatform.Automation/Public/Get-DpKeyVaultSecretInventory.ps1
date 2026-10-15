function Get-DpKeyVaultSecretInventory {
    <#
    .SYNOPSIS
        Lists secret metadata (never values) for a vault with an expiry classification.
    .EXAMPLE
        Get-DpKeyVaultSecretInventory -VaultName kv-dp-data-prod-01 -WarningDays 30
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param (
        [Parameter(Mandatory)]
        [string]$VaultName,

        [ValidateRange(1, 365)]
        [int]$WarningDays = 30
    )

    $inventory = foreach ($secret in @(Get-AzKeyVaultSecret -VaultName $VaultName)) {
        $detail = Get-AzKeyVaultSecret -VaultName $VaultName -Name $secret.Name
        $expiry = Get-DpSecretExpiryStatus -Expires $detail.Expires -WarningDays $WarningDays

        [pscustomobject]@{
            VaultName       = $VaultName
            SecretName      = $secret.Name
            Enabled         = $detail.Enabled
            Created         = $detail.Created
            Updated         = $detail.Updated
            Expires         = $detail.Expires
            DaysUntilExpiry = $expiry.DaysUntilExpiry
            ExpiryStatus    = $expiry.Status
            ContentType     = $detail.ContentType
        }
    }

    return @($inventory)
}
