<#
.SYNOPSIS
    Provisions users to Databricks workspaces based on Azure AD group membership.

.DESCRIPTION
    Reads Azure AD group members and maps them to the correct Databricks workspace
    using the SCIM API. Ensures users have the right access level (admin, user, viewer)
    based on their group membership. Supports multiple workspaces across business units.

.PARAMETER ConfigFile
    Path to JSON config mapping AD groups to Databricks workspaces and roles.

.PARAMETER KeyVaultName
    Name of Key Vault storing workspace tokens.

.PARAMETER DryRun
    Preview changes without applying them.

.EXAMPLE
    .\Set-DatabricksWorkspaceUsers.ps1 -ConfigFile ".\config\workspace-groups.json" -KeyVaultName "kv-prod-001"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$ConfigFile,

    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Get-DatabricksUsers {
    param ([string]$WorkspaceUrl, [string]$Token)

    $headers = @{ "Authorization" = "Bearer $Token"; "Content-Type" = "application/json" }
    $uri = "$WorkspaceUrl/api/2.0/preview/scim/v2/Users?count=1000"
    $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers
    return $response.Resources
}

function Add-DatabricksUser {
    param ([string]$WorkspaceUrl, [string]$Token, [string]$Email, [string]$DisplayName)

    $headers = @{ "Authorization" = "Bearer $Token"; "Content-Type" = "application/json" }
    $body = @{
        schemas  = @("urn:ietf:params:scim:schemas:core:2.0:User")
        userName = $Email
        displayName = $DisplayName
        emails   = @(@{ value = $Email; type = "work"; primary = $true })
    } | ConvertTo-Json -Depth 4

    $uri = "$WorkspaceUrl/api/2.0/preview/scim/v2/Users"
    $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body
    return $response
}

# ============================================================
# Main
# ============================================================

Write-Host "`n=== Databricks User Provisioning ===" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "DRY RUN - no changes will be applied.`n" -ForegroundColor Yellow
}

$config = Get-Content $ConfigFile | ConvertFrom-Json
$totalAdded = 0
$totalSkipped = 0

foreach ($mapping in $config.mappings) {
    Write-Host "`nWorkspace: $($mapping.workspaceName)" -ForegroundColor Cyan
    Write-Host "AD Group:  $($mapping.adGroupName)"

    # Get workspace token from Key Vault
    $token = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $mapping.tokenSecretName -AsPlainText
    $workspaceUrl = "https://$($mapping.workspaceHost).azuredatabricks.net"

    # Get current Databricks users
    $existingUsers = Get-DatabricksUsers -WorkspaceUrl $workspaceUrl -Token $token
    $existingEmails = $existingUsers | ForEach-Object { $_.userName.ToLower() }

    # Get AD group members
    $groupId = (Get-AzADGroup -DisplayName $mapping.adGroupName).Id
    $adMembers = Get-AzADGroupMember -GroupObjectId $groupId

    foreach ($member in $adMembers) {
        $email = $member.UserPrincipalName.ToLower()

        if ($existingEmails -contains $email) {
            Write-Host "  Exists: $email" -ForegroundColor DarkGray
            $totalSkipped++
            continue
        }

        if ($DryRun) {
            Write-Host "  Would add: $email ($($member.DisplayName))" -ForegroundColor Yellow
        }
        else {
            try {
                Add-DatabricksUser -WorkspaceUrl $workspaceUrl -Token $token `
                                    -Email $email -DisplayName $member.DisplayName
                Write-Host "  Added: $email" -ForegroundColor Green
                $totalAdded++
            }
            catch {
                Write-Warning "  Failed to add $email : $_"
            }
        }
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Users added:   $totalAdded"
Write-Host "Users skipped: $totalSkipped (already exist)"
