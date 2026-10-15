<#
.SYNOPSIS
    Removes group members who are not on an authoritative (HR) user list.

.DESCRIPTION
    Stale-member detection is in Get-DpStaleGroupMember and is unit tested.
    This wrapper fetches membership, writes an audit CSV and removes members
    only when -Apply is given.

.EXAMPLE
    ./Remove-StaleADGroupMembers.ps1 -GroupName 'dp-databricks-prod-users' -AuthorisedUsersCsv ./active_users.csv -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string]$GroupName,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$AuthorisedUsersCsv,

    [string]$AuditLogPath = './logs',

    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../modules/DataPlatform.Automation/DataPlatform.Automation.psd1') -Force

Write-DpLog -Message "Stale member clean-up for group '$GroupName'"

$group = Get-AzADGroup -DisplayName $GroupName
if (-not $group) {
    throw "Group not found: $GroupName"
}

$authorised = @((Import-Csv -Path $AuthorisedUsersCsv).UserPrincipalName)
$members = @(Get-AzADGroupMember -GroupObjectId $group.Id)
$stale = Get-DpStaleGroupMember -CurrentMember $members -AuthorisedUserPrincipalName $authorised

Write-DpLog -Message "Members: $($members.Count) | Authorised list: $($authorised.Count) | Stale: $($stale.Count)"

$audit = foreach ($member in $stale) {
    $removed = $false
    if ($Apply -and $PSCmdlet.ShouldProcess($member.UserPrincipalName, "Remove from $GroupName")) {
        Remove-AzADGroupMember -GroupObjectId $group.Id -MemberObjectId $member.Id
        $removed = $true
        Write-DpLog -Message "  Removed: $($member.UserPrincipalName)" -Level Warning
    } else {
        Write-DpLog -Message "  Would remove: $($member.UserPrincipalName)"
    }

    [pscustomobject]@{
        Timestamp         = (Get-Date).ToString('s')
        Group             = $GroupName
        UserPrincipalName = $member.UserPrincipalName
        Action            = if ($removed) { 'Removed' } else { 'Pending' }
    }
}

if ($audit) {
    if (-not (Test-Path -Path $AuditLogPath)) {
        New-Item -ItemType Directory -Path $AuditLogPath -Force | Out-Null
    }
    $logFile = Join-Path -Path $AuditLogPath -ChildPath "ad-cleanup-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    $audit | Export-Csv -Path $logFile -NoTypeInformation
    Write-DpLog -Message "Audit log: $logFile" -Level Success
}

[pscustomobject]@{
    Group   = $GroupName
    Kept    = $members.Count - $stale.Count
    Stale   = $stale.Count
    Applied = [bool]$Apply
}
