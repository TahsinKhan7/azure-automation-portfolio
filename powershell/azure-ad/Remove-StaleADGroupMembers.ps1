<#
.SYNOPSIS
    Removes stale users from Azure AD groups based on HR export or disable date.
.DESCRIPTION
    Compares AD group membership against an authoritative user list (e.g. from HR)
    and removes users no longer authorised. Logs all removals for audit trail.
.EXAMPLE
    .\Remove-StaleADGroupMembers.ps1 -GroupName "DBX-Prod-Users" -AuthorisedUsersCsv ".\active_users.csv"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$GroupName,
    [Parameter(Mandatory = $true)][string]$AuthorisedUsersCsv,
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== Stale Group Member Cleanup ===" -ForegroundColor Cyan
Write-Host "Group: $GroupName"

$group = Get-AzADGroup -DisplayName $GroupName
if (-not $group) { Write-Error "Group not found: $GroupName"; exit 1 }

$authorised = (Import-Csv $AuthorisedUsersCsv).UserPrincipalName | ForEach-Object { $_.ToLower() }
$currentMembers = Get-AzADGroupMember -GroupObjectId $group.Id

$removeCount = 0
$keepCount = 0
$auditLog = @()

foreach ($member in $currentMembers) {
    $upn = $member.UserPrincipalName.ToLower()
    
    if ($authorised -contains $upn) {
        $keepCount++
        continue
    }

    if ($Apply) {
        Remove-AzADGroupMember -GroupObjectId $group.Id -MemberObjectId $member.Id
        Write-Host "  Removed: $upn" -ForegroundColor Yellow
    }
    else {
        Write-Host "  Would remove: $upn" -ForegroundColor DarkGray
    }

    $auditLog += [PSCustomObject]@{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Group     = $GroupName
        User      = $upn
        Action    = if ($Apply) { "Removed" } else { "Pending" }
    }
    $removeCount++
}

# Export audit log
if ($auditLog.Count -gt 0) {
    $logPath = ".\logs\ad-cleanup-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    $auditLog | Export-Csv -Path $logPath -NoTypeInformation
    Write-Host "`nAudit log: $logPath" -ForegroundColor Green
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Kept:    $keepCount"
Write-Host "Removed: $removeCount"
