function Get-DpResourceGroupFromResourceId {
    <#
    .SYNOPSIS
        Extracts the resource group name from an Azure resource ID.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [AllowEmptyString()]
        [AllowNull()]
        [string]$ResourceId
    )

    if ([string]::IsNullOrWhiteSpace($ResourceId)) {
        return $null
    }

    $segments = $ResourceId.Trim('/') -split '/'
    for ($i = 0; $i -lt $segments.Count - 1; $i++) {
        if ($segments[$i] -ieq 'resourceGroups') {
            return $segments[$i + 1]
        }
    }

    return $null
}
