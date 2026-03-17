<#
.SYNOPSIS
    Manages Azure RBAC role assignments across subscriptions and resource groups.
.DESCRIPTION
    Assigns, audits or removes RBAC roles based on a config file.
    Supports subscription-level, resource group-level and resource-level assignments.
.EXAMPLE
    .\Set-AzureRBAC.ps1 -ConfigFile ".\config\rbac-assignments.json" -Apply
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$ConfigFile,
    [switch]$Apply,
    [switch]$AuditOnly
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== RBAC Assignment Manager ===" -ForegroundColor Cyan

$config = Get-Content $ConfigFile | ConvertFrom-Json
$assigned = 0; $skipped = 0; $removed = 0

foreach ($entry in $config.assignments) {
    $principalId = $null
    
    # Resolve principal (user, group, or service principal)
    switch ($entry.principalType) {
        "Group" {
            $grp = Get-AzADGroup -DisplayName $entry.principalName
            $principalId = $grp.Id
        }
        "User" {
            $usr = Get-AzADUser -UserPrincipalName $entry.principalName
            $principalId = $usr.Id
        }
        "ServicePrincipal" {
            $sp = Get-AzADServicePrincipal -DisplayName $entry.principalName
            $principalId = $sp.Id
        }
    }

    if (-not $principalId) {
        Write-Warning "  Principal not found: $($entry.principalName)"
        $skipped++
        continue
    }

    if ($AuditOnly) {
        $existing = Get-AzRoleAssignment -ObjectId $principalId -Scope $entry.scope -ErrorAction SilentlyContinue
        $hasRole = $existing | Where-Object { $_.RoleDefinitionName -eq $entry.roleName }
        $status = if ($hasRole) { "ASSIGNED" } else { "MISSING" }
        Write-Host "  [$status] $($entry.principalName) -> $($entry.roleName) @ $($entry.scope)" -ForegroundColor $(if ($hasRole) { "Green" } else { "Yellow" })
        continue
    }

    if ($entry.action -eq "Remove" -and $Apply) {
        Remove-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName $entry.roleName -Scope $entry.scope
        Write-Host "  Removed: $($entry.principalName) -> $($entry.roleName)" -ForegroundColor Yellow
        $removed++
    }
    elseif ($Apply) {
        try {
            New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName $entry.roleName -Scope $entry.scope -ErrorAction Stop
            Write-Host "  Assigned: $($entry.principalName) -> $($entry.roleName)" -ForegroundColor Green
            $assigned++
        }
        catch {
            if ($_.Exception.Message -like "*already exists*") {
                Write-Host "  Exists: $($entry.principalName) -> $($entry.roleName)" -ForegroundColor DarkGray
                $skipped++
            }
            else { throw }
        }
    }
}

Write-Host "`nAssigned: $assigned | Removed: $removed | Skipped: $skipped"
