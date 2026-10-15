function Get-DpStaleGroupMember {
    <#
    .SYNOPSIS
        Identifies group members that are not on the authorised user list.
    .DESCRIPTION
        Compares current members (objects with UserPrincipalName, Id and
        DisplayName, as returned by Get-AzADGroupMember) against an authoritative
        list of user principal names. Matching is case-insensitive. Members
        without a UserPrincipalName (nested groups, service principals) are
        skipped because the HR list cannot vouch for them either way.

        Refuses to run against an empty authorised list: that would mark every
        member stale, which is never the intent.
    .EXAMPLE
        Get-DpStaleGroupMember -CurrentMember $members -AuthorisedUserPrincipalName $hrList.UserPrincipalName
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$CurrentMember,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$AuthorisedUserPrincipalName
    )

    $authorised = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($upn in $AuthorisedUserPrincipalName) {
        if (-not [string]::IsNullOrWhiteSpace($upn)) {
            [void]$authorised.Add($upn.Trim())
        }
    }

    if ($authorised.Count -eq 0) {
        throw 'The authorised user list is empty. Refusing to continue because every member would be treated as stale.'
    }

    $stale = foreach ($member in $CurrentMember) {
        $upn = [string]$member.UserPrincipalName
        if ([string]::IsNullOrWhiteSpace($upn)) {
            Write-Verbose -Message "Skipping member '$($member.DisplayName)' ($($member.Id)) with no user principal name."
            continue
        }

        if (-not $authorised.Contains($upn.Trim())) {
            [pscustomobject]@{
                UserPrincipalName = $upn.ToLowerInvariant()
                Id                = $member.Id
                DisplayName       = $member.DisplayName
                Action            = 'Remove'
            }
        }
    }

    return @($stale)
}
