function Compare-DpVariableGroup {
    <#
    .SYNOPSIS
        Computes the change set between an existing Azure DevOps variable group and the desired state.
    .DESCRIPTION
        Desired values may be plain strings or hashtables of the form
        @{ value = '...'; isSecret = $true }. Existing secret values are never
        returned by the API, so secrets are treated as unchanged unless
        -ForceSecretUpdate is given. Variables present in the group but not in
        the desired set are left alone unless -RemoveUnmanaged is given.
    .EXAMPLE
        Compare-DpVariableGroup -Existing $group.variables -Desired @{ Environment = 'dev'; ApiKey = @{ value = 'x'; isSecret = $true } }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [AllowNull()]
        [hashtable]$Existing,

        [Parameter(Mandatory)]
        [hashtable]$Desired,

        [switch]$RemoveUnmanaged,

        [switch]$ForceSecretUpdate
    )

    $normalisedDesired = @{}
    foreach ($key in $Desired.Keys) {
        $item = $Desired[$key]
        if ($item -is [hashtable] -or $item -is [System.Collections.IDictionary]) {
            $normalisedDesired[$key] = @{ value = [string]$item['value']; isSecret = [bool]$item['isSecret'] }
        } else {
            $normalisedDesired[$key] = @{ value = [string]$item; isSecret = $false }
        }
    }

    $toAdd = [System.Collections.Generic.List[string]]::new()
    $toUpdate = [System.Collections.Generic.List[string]]::new()
    $toRemove = [System.Collections.Generic.List[string]]::new()
    $merged = @{}

    if ($null -eq $Existing) {
        foreach ($key in $normalisedDesired.Keys) {
            $toAdd.Add($key)
            $merged[$key] = $normalisedDesired[$key]
        }

        return [pscustomobject]@{
            Action    = 'Create'
            ToAdd     = @($toAdd | Sort-Object)
            ToUpdate  = @()
            ToRemove  = @()
            Variables = $merged
        }
    }

    foreach ($key in $Existing.Keys) {
        $current = $Existing[$key]
        $merged[$key] = @{ value = [string]$current.value; isSecret = [bool]$current.isSecret }
    }

    foreach ($key in $normalisedDesired.Keys) {
        $want = $normalisedDesired[$key]
        $existingKey = $Existing.Keys | Where-Object { $_ -ieq $key } | Select-Object -First 1

        if (-not $existingKey) {
            $toAdd.Add($key)
            $merged[$key] = $want
            continue
        }

        $have = $merged[$existingKey]

        if ($want.isSecret) {
            if ($ForceSecretUpdate -or -not $have.isSecret) {
                $toUpdate.Add($existingKey)
                $merged[$existingKey] = $want
            }
            continue
        }

        if ($have.isSecret -ne $want.isSecret -or $have.value -cne $want.value) {
            $toUpdate.Add($existingKey)
            $merged[$existingKey] = $want
        }
    }

    if ($RemoveUnmanaged) {
        foreach ($key in @($Existing.Keys)) {
            if (-not ($normalisedDesired.Keys | Where-Object { $_ -ieq $key })) {
                $toRemove.Add($key)
                $merged.Remove($key)
            }
        }
    }

    # Unchanged secrets are sent back with isSecret and no value, which the service
    # interprets as "keep the stored value".
    foreach ($key in @($merged.Keys)) {
        if ($merged[$key].isSecret -and $key -notin $toAdd -and $key -notin $toUpdate) {
            $merged[$key] = @{ isSecret = $true }
        }
    }

    $action = if ($toAdd.Count + $toUpdate.Count + $toRemove.Count -gt 0) { 'Update' } else { 'NoChange' }

    return [pscustomobject]@{
        Action    = $action
        ToAdd     = @($toAdd | Sort-Object)
        ToUpdate  = @($toUpdate | Sort-Object)
        ToRemove  = @($toRemove | Sort-Object)
        Variables = $merged
    }
}
