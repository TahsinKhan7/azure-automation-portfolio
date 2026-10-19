<#
.SYNOPSIS
    Creates the medallion folder hierarchy in an ADLS Gen2 container and applies group ACLs from a config file.

.DESCRIPTION
    Folder layout comes from Get-DpMedallionFolderLayout; the ACL plan is built
    and validated by ConvertTo-DpDataLakeAclPlan (unit tested) before any
    change is made. Without -Apply the script prints the plan only.

.EXAMPLE
    ./Set-DataLakeACLs.ps1 -StorageAccount stdpdataprod01 -Container bronze -ConfigFile ./config/datalake-acls.json -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string]$StorageAccount,

    [Parameter(Mandatory)]
    [string]$Container,

    [string]$ConfigFile = './config/datalake-acls.json',

    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../modules/DataPlatform.Automation/DataPlatform.Automation.psd1') -Force

Write-DpLog -Message "Data Lake ACLs: $StorageAccount/$Container"

$context = New-AzStorageContext -StorageAccountName $StorageAccount -UseConnectedAccount

foreach ($folder in Get-DpMedallionFolderLayout) {
    $existing = Get-AzDataLakeGen2Item -Context $context -FileSystem $Container -Path $folder -ErrorAction SilentlyContinue
    if ($existing) {
        Write-DpLog -Message "  Exists: $folder" -Level Debug
        continue
    }
    if ($Apply -and $PSCmdlet.ShouldProcess("$Container/$folder", 'Create directory')) {
        New-AzDataLakeGen2Item -Context $context -FileSystem $Container -Path $folder -Directory | Out-Null
        Write-DpLog -Message "  Created: $folder" -Level Success
    } else {
        Write-DpLog -Message "  Would create: $folder"
    }
}

if (-not (Test-Path -Path $ConfigFile)) {
    Write-DpLog -Message "No ACL config at $ConfigFile; folders only." -Level Warning
    return
}

$rules = @((Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json).rules)
$groupIds = @{}
foreach ($groupName in ($rules.adGroup | Select-Object -Unique)) {
    $group = Get-AzADGroup -DisplayName $groupName -ErrorAction SilentlyContinue
    if ($group) { $groupIds[$groupName] = $group.Id }
}

$plan = ConvertTo-DpDataLakeAclPlan -Rule $rules -GroupObjectId $groupIds

foreach ($entry in $plan) {
    $acl = Set-AzDataLakeGen2ItemAclObject -AccessControlType group -EntityId $entry.GroupObjectId -Permission $entry.Permissions
    if ($entry.ApplyDefault) {
        $acl = Set-AzDataLakeGen2ItemAclObject -AccessControlType group -EntityId $entry.GroupObjectId -Permission $entry.Permissions -DefaultScope -InputObject $acl
    }

    if ($Apply -and $PSCmdlet.ShouldProcess("$Container/$($entry.Path)", "Grant $($entry.GroupName) $($entry.Permissions)")) {
        Update-AzDataLakeGen2Item -Context $context -FileSystem $Container -Path $entry.Path -Acl $acl | Out-Null
        Write-DpLog -Message "  ACL set: $($entry.GroupName) -> $($entry.Permissions) on $($entry.Path)" -Level Success
    } else {
        Write-DpLog -Message "  Would set: $($entry.GroupName) -> $($entry.Permissions) on $($entry.Path)"
    }
}

$plan
