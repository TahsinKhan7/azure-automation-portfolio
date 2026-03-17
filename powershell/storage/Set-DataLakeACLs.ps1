<#
.SYNOPSIS
    Manages Azure Data Lake Storage Gen2 folder structures and ACL permissions.
.DESCRIPTION
    Creates medallion architecture folder hierarchy (bronze/silver/gold) and sets
    POSIX ACLs for AD groups on each layer. Ensures consistent access patterns
    across data lake containers.
.EXAMPLE
    .\Set-DataLakeACLs.ps1 -StorageAccount "stproddatalake001" -Container "datalake" -Apply
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$StorageAccount,
    [Parameter(Mandatory = $true)][string]$Container,
    [string]$ConfigFile = ".\config\datalake-acls.json",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== Data Lake ACL Manager ===" -ForegroundColor Cyan
Write-Host "Storage Account: $StorageAccount"
Write-Host "Container:       $Container`n"

$ctx = New-AzStorageContext -StorageAccountName $StorageAccount -UseConnectedAccount

# Define medallion folder structure
$folders = @(
    "bronze", "bronze/raw", "bronze/landing",
    "silver", "silver/cleansed", "silver/standardised",
    "gold", "gold/aggregated", "gold/reporting",
    "_checkpoints", "_schemas", "_logs"
)

# Create folders
foreach ($folder in $folders) {
    $existing = Get-AzDataLakeGen2Item -Context $ctx -FileSystem $Container -Path $folder -ErrorAction SilentlyContinue
    if (-not $existing) {
        if ($Apply) {
            New-AzDataLakeGen2Item -Context $ctx -FileSystem $Container -Path $folder -Directory
            Write-Host "  Created: $folder" -ForegroundColor Green
        }
        else {
            Write-Host "  Would create: $folder" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "  Exists: $folder" -ForegroundColor Gray
    }
}

# Apply ACLs from config
if (Test-Path $ConfigFile) {
    $aclConfig = Get-Content $ConfigFile | ConvertFrom-Json
    
    foreach ($rule in $aclConfig.rules) {
        $groupId = (Get-AzADGroup -DisplayName $rule.adGroup -ErrorAction SilentlyContinue).Id
        
        if (-not $groupId) {
            Write-Warning "  AD group not found: $($rule.adGroup)"
            continue
        }

        $permissions = $rule.permissions  # e.g. "rwx", "r-x", "r--"
        
        foreach ($path in $rule.paths) {
            $acl = Set-AzDataLakeGen2ItemAclObject -AccessControlType group `
                    -EntityId $groupId -Permission $permissions
            
            if ($Apply) {
                Update-AzDataLakeGen2Item -Context $ctx -FileSystem $Container `
                    -Path $path -Acl $acl
                Write-Host "  ACL set: $($rule.adGroup) -> $permissions on $path" -ForegroundColor Green
            }
            else {
                Write-Host "  Would set: $($rule.adGroup) -> $permissions on $path" -ForegroundColor DarkGray
            }
        }
    }
}

Write-Host "`nData Lake structure and ACLs configured." -ForegroundColor Cyan
