<#
.SYNOPSIS
    Creates Entra ID security groups from a JSON definition, with members and nested groups.

.DESCRIPTION
    Idempotent: existing groups are reused, existing memberships are skipped.
    Without -Apply the script reports what it would do.

.EXAMPLE
    ./New-AzureADGroups.ps1 -ConfigFile ./config/ad-groups.json -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$ConfigFile,

    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../modules/DataPlatform.Automation/DataPlatform.Automation.psd1') -Force

Write-DpLog -Message 'Entra ID group provisioning'
if (-not $Apply) {
    Write-DpLog -Message 'Preview mode: use -Apply to commit changes.' -Level Warning
}

$config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
$created = 0
$membersAdded = 0
$nested = 0

function Add-MemberIfMissing {
    param ([string]$GroupId, [string]$MemberId, [string]$Label)

    try {
        Add-AzADGroupMember -TargetGroupObjectId $GroupId -MemberObjectId $MemberId -ErrorAction Stop
        Write-DpLog -Message "    Added: $Label" -Level Success
        return $true
    } catch {
        if ($_.Exception.Message -like '*already exist*') {
            Write-DpLog -Message "    Already a member: $Label" -Level Debug
            return $false
        }
        throw
    }
}

foreach ($group in $config.groups) {
    $mailNickname = ($group.displayName -replace '\s', '-') -replace '[^a-zA-Z0-9\-]', ''
    $existing = Get-AzADGroup -DisplayName $group.displayName -ErrorAction SilentlyContinue

    if (-not $existing) {
        if ($Apply -and $PSCmdlet.ShouldProcess($group.displayName, 'Create security group')) {
            $existing = New-AzADGroup -DisplayName $group.displayName -MailNickname $mailNickname -Description $group.description -SecurityEnabled
            Write-DpLog -Message "  Created: $($group.displayName) ($($existing.Id))" -Level Success
            $created++
        } else {
            Write-DpLog -Message "  Would create: $($group.displayName)"
            continue
        }
    } else {
        Write-DpLog -Message "  Exists: $($group.displayName)" -Level Debug
    }

    foreach ($upn in @($group.members)) {
        $user = Get-AzADUser -UserPrincipalName $upn -ErrorAction SilentlyContinue
        if (-not $user) {
            Write-DpLog -Message "    User not found: $upn" -Level Warning
            continue
        }
        if ($Apply -and $PSCmdlet.ShouldProcess($group.displayName, "Add member $upn")) {
            if (Add-MemberIfMissing -GroupId $existing.Id -MemberId $user.Id -Label $upn) { $membersAdded++ }
        }
    }

    foreach ($childName in @($group.nestedGroups)) {
        $child = Get-AzADGroup -DisplayName $childName -ErrorAction SilentlyContinue
        if (-not $child) {
            Write-DpLog -Message "    Nested group not found: $childName" -Level Warning
            continue
        }
        if ($Apply -and $PSCmdlet.ShouldProcess($group.displayName, "Nest group $childName")) {
            if (Add-MemberIfMissing -GroupId $existing.Id -MemberId $child.Id -Label "$childName -> $($group.displayName)") { $nested++ }
        }
    }
}

[pscustomobject]@{
    GroupsCreated = $created
    MembersAdded  = $membersAdded
    GroupsNested  = $nested
}
