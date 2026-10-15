function ConvertTo-DpDataLakeAclPlan {
    <#
    .SYNOPSIS
        Turns ACL rules (group, permissions, paths) into an ordered list of ACL entries to apply.
    .DESCRIPTION
        Validates each permission string is POSIX (rwx, r-x, r--, ...), resolves
        group names to object IDs through the supplied map, skips (with a
        warning) groups that cannot be resolved, and orders entries parent-first
        so that default ACLs on directories are set before children.
    .EXAMPLE
        $rules = (Get-Content .\datalake-acls.json | ConvertFrom-Json).rules
        ConvertTo-DpDataLakeAclPlan -Rule $rules -GroupObjectId @{ 'data-engineers' = '<guid>' }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rule,

        [Parameter(Mandatory)]
        [hashtable]$GroupObjectId
    )

    $entries = foreach ($item in $Rule) {
        $permissions = [string]$item.permissions
        if ($permissions -cnotmatch '^[r-][w-][x-]$') {
            throw "Rule for group '$($item.adGroup)' has invalid permissions '$permissions'. Expected a POSIX triple such as rwx or r-x."
        }

        $objectId = $GroupObjectId[[string]$item.adGroup]
        if ([string]::IsNullOrWhiteSpace($objectId)) {
            Write-Warning -Message "Group '$($item.adGroup)' could not be resolved; its rule is skipped."
            continue
        }

        $applyDefault = if ($null -eq $item.applyDefault) { $true } else { [bool]$item.applyDefault }

        foreach ($path in @($item.paths)) {
            [pscustomobject]@{
                Path          = ([string]$path).Trim('/')
                GroupName     = [string]$item.adGroup
                GroupObjectId = [string]$objectId
                Permissions   = $permissions
                ApplyDefault  = $applyDefault
            }
        }
    }

    return @($entries | Sort-Object -Property @{ Expression = { ($_.Path -split '/').Count } }, Path, GroupName)
}
