function Test-DpStorageAccountCompliance {
    <#
    .SYNOPSIS
        Evaluates a storage account against the platform security baseline.
    .DESCRIPTION
        The baseline: HTTPS only, TLS 1.2 minimum, no anonymous blob access,
        firewall default action Deny and (optionally) Shared Key disabled and
        mandatory tags present. Accepts the object returned by
        Get-AzStorageAccount or any object with the same property names.
    .EXAMPLE
        Get-AzStorageAccount | ForEach-Object { Test-DpStorageAccountCompliance -StorageAccount $_ }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [object]$StorageAccount,

        [switch]$RequireSharedKeyDisabled,

        [string[]]$RequiredTag = @()
    )

    $findings = [System.Collections.Generic.List[string]]::new()

    if ($StorageAccount.EnableHttpsTrafficOnly -ne $true) {
        $findings.Add('HTTPS-only traffic is not enforced')
    }

    if ($StorageAccount.MinimumTlsVersion -ne 'TLS1_2') {
        $findings.Add("Minimum TLS version is '$($StorageAccount.MinimumTlsVersion)' (expected TLS1_2)")
    }

    if ($StorageAccount.AllowBlobPublicAccess -eq $true) {
        $findings.Add('Anonymous blob access is allowed')
    }

    if ($StorageAccount.NetworkRuleSet.DefaultAction -ne 'Deny') {
        $findings.Add("Firewall default action is '$($StorageAccount.NetworkRuleSet.DefaultAction)' (expected Deny)")
    }

    if ($RequireSharedKeyDisabled -and $StorageAccount.AllowSharedKeyAccess -ne $false) {
        $findings.Add('Shared Key access is enabled')
    }

    foreach ($tag in $RequiredTag) {
        $tags = $StorageAccount.Tags
        if ($null -eq $tags -or -not ($tags.Keys | Where-Object { $_ -ieq $tag })) {
            $findings.Add("Required tag '$tag' is missing")
        }
    }

    return [pscustomobject]@{
        Name          = $StorageAccount.StorageAccountName
        ResourceGroup = $StorageAccount.ResourceGroupName
        IsCompliant   = ($findings.Count -eq 0)
        FindingCount  = $findings.Count
        Findings      = @($findings)
    }
}
