<#
.SYNOPSIS
    Applies, removes or audits Azure RBAC role assignments from a JSON definition.

.DESCRIPTION
    Each entry names a principal (group, user or service principal), a role and
    a scope. -AuditOnly reports drift without changing anything; -Apply makes
    the changes. Existing assignments are skipped.

.EXAMPLE
    ./Set-AzureRBAC.ps1 -ConfigFile ./config/rbac-assignments.json -AuditOnly
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$ConfigFile,

    [switch]$Apply,

    [switch]$AuditOnly
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../modules/DataPlatform.Automation/DataPlatform.Automation.psd1') -Force

Write-DpLog -Message 'RBAC assignment manager'

$config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
$assigned = 0
$removed = 0
$skipped = 0

$results = foreach ($entry in $config.assignments) {
    $principal = switch ($entry.principalType) {
        'Group' { Get-AzADGroup -DisplayName $entry.principalName -ErrorAction SilentlyContinue }
        'User' { Get-AzADUser -UserPrincipalName $entry.principalName -ErrorAction SilentlyContinue }
        'ServicePrincipal' { Get-AzADServicePrincipal -DisplayName $entry.principalName -ErrorAction SilentlyContinue }
        default { $null }
    }

    if (-not $principal) {
        Write-DpLog -Message "  Principal not found: $($entry.principalName) ($($entry.principalType))" -Level Warning
        $skipped++
        continue
    }

    $existing = Get-AzRoleAssignment -ObjectId $principal.Id -Scope $entry.scope -ErrorAction SilentlyContinue |
        Where-Object { $_.RoleDefinitionName -eq $entry.roleName -and $_.Scope -eq $entry.scope }
    $hasRole = [bool]$existing
    $status = if ($hasRole) { 'Assigned' } else { 'Missing' }

    if ($AuditOnly) {
        Write-DpLog -Message "  [$status] $($entry.principalName) -> $($entry.roleName) @ $($entry.scope)"
    } elseif ($entry.action -eq 'Remove') {
        if ($hasRole -and $Apply -and $PSCmdlet.ShouldProcess($entry.scope, "Remove $($entry.roleName) from $($entry.principalName)")) {
            Remove-AzRoleAssignment -ObjectId $principal.Id -RoleDefinitionName $entry.roleName -Scope $entry.scope
            $removed++
            $status = 'Removed'
        }
    } elseif (-not $hasRole) {
        if ($Apply -and $PSCmdlet.ShouldProcess($entry.scope, "Assign $($entry.roleName) to $($entry.principalName)")) {
            New-AzRoleAssignment -ObjectId $principal.Id -RoleDefinitionName $entry.roleName -Scope $entry.scope | Out-Null
            $assigned++
            $status = 'Assigned'
        } else {
            $status = 'WouldAssign'
        }
    } else {
        $skipped++
    }

    [pscustomobject]@{
        Principal = $entry.principalName
        Role      = $entry.roleName
        Scope     = $entry.scope
        Status    = $status
    }
}

Write-DpLog -Message "Assigned: $assigned | Removed: $removed | Skipped: $skipped"
$results
