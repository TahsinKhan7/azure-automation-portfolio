<#
.SYNOPSIS
    Creates and manages Azure AD security groups with nested group support.
.DESCRIPTION
    Bulk creates AD groups from a config file, adds members and nests groups
    following enterprise naming conventions. Supports RBAC-aligned group structures.
.EXAMPLE
    .\New-AzureADGroups.ps1 -ConfigFile ".\config\ad-groups.json" -Apply
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$ConfigFile,
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== Azure AD Group Management ===" -ForegroundColor Cyan
if (-not $Apply) { Write-Host "PREVIEW MODE - use -Apply to commit changes.`n" -ForegroundColor Yellow }

$config = Get-Content $ConfigFile | ConvertFrom-Json
$created = 0; $updated = 0; $nested = 0

foreach ($group in $config.groups) {
    $displayName = $group.displayName
    $description = $group.description
    $mailNickname = $displayName -replace '\s', '-' -replace '[^a-zA-Z0-9\-]', ''

    # Check if group exists
    $existing = Get-AzADGroup -DisplayName $displayName -ErrorAction SilentlyContinue

    if (-not $existing) {
        if ($Apply) {
            $newGroup = New-AzADGroup -DisplayName $displayName `
                                       -MailNickname $mailNickname `
                                       -Description $description `
                                       -SecurityEnabled
            Write-Host "  Created: $displayName (ID: $($newGroup.Id))" -ForegroundColor Green
            $existing = $newGroup
            $created++
        }
        else {
            Write-Host "  Would create: $displayName" -ForegroundColor DarkGray
            continue
        }
    }
    else {
        Write-Host "  Exists: $displayName" -ForegroundColor Gray
    }

    # Add direct members (users)
    if ($group.members) {
        foreach ($upn in $group.members) {
            $user = Get-AzADUser -UserPrincipalName $upn -ErrorAction SilentlyContinue
            if ($user -and $Apply) {
                try {
                    Add-AzADGroupMember -TargetGroupObjectId $existing.Id -MemberObjectId $user.Id -ErrorAction SilentlyContinue
                    Write-Host "    Added member: $upn" -ForegroundColor Green
                }
                catch {
                    if ($_.Exception.Message -like "*already exist*") {
                        Write-Host "    Already member: $upn" -ForegroundColor DarkGray
                    }
                    else { Write-Warning "    Failed: $upn - $_" }
                }
                $updated++
            }
        }
    }

    # Nest child groups
    if ($group.nestedGroups) {
        foreach ($childGroupName in $group.nestedGroups) {
            $childGroup = Get-AzADGroup -DisplayName $childGroupName -ErrorAction SilentlyContinue
            if ($childGroup -and $Apply) {
                try {
                    Add-AzADGroupMember -TargetGroupObjectId $existing.Id -MemberObjectId $childGroup.Id -ErrorAction SilentlyContinue
                    Write-Host "    Nested group: $childGroupName -> $displayName" -ForegroundColor Green
                    $nested++
                }
                catch {
                    if ($_.Exception.Message -like "*already exist*") {
                        Write-Host "    Already nested: $childGroupName" -ForegroundColor DarkGray
                    }
                }
            }
        }
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Groups created:  $created"
Write-Host "Members updated: $updated"
Write-Host "Groups nested:   $nested"
