<#
.SYNOPSIS
    Bulk updates Azure AD user attributes and syncs email aliases across services.

.DESCRIPTION
    Reads a CSV of user mappings, updates their Azure AD email attributes and optionally
    syncs changes to downstream services like Databricks. Designed for scenarios where
    enterprise email migrations cause authentication issues in external-facing resources.

.PARAMETER InputCsv
    Path to CSV with columns: UserPrincipalName, OldEmail, NewEmail, DatabricksWorkspace

.PARAMETER UpdateAzureAD
    Switch to apply changes to Azure AD. Without this, runs in preview mode.

.PARAMETER SyncToDatabricks
    Switch to also update the user's email in Databricks workspaces.

.EXAMPLE
    .\Sync-AzureADUsers.ps1 -InputCsv ".\users.csv" -UpdateAzureAD -SyncToDatabricks
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory = $true)]
    [string]$InputCsv,

    [Parameter(Mandatory = $false)]
    [switch]$UpdateAzureAD,

    [Parameter(Mandatory = $false)]
    [switch]$SyncToDatabricks
)

$ErrorActionPreference = "Stop"

# ============================================================
# Functions
# ============================================================

function Update-UserEmailInAD {
    param (
        [string]$UserPrincipalName,
        [string]$OldEmail,
        [string]$NewEmail
    )

    $user = Get-AzADUser -UserPrincipalName $UserPrincipalName

    if (-not $user) {
        Write-Warning "  User not found in Azure AD: $UserPrincipalName"
        return $false
    }

    # Remove the old proxy address if present
    $proxyAddresses = $user.ProxyAddresses | Where-Object { $_ -ne "smtp:$OldEmail" }

    # Add new email as proxy address if not already present
    if ($proxyAddresses -notcontains "smtp:$NewEmail") {
        $proxyAddresses += "smtp:$NewEmail"
    }

    try {
        Update-AzADUser -ObjectId $user.Id -OtherMail @($NewEmail)
        Write-Host "  Updated AD: $UserPrincipalName -> $NewEmail" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "  Failed to update $UserPrincipalName : $_"
        return $false
    }
}

function Update-UserEmailInDatabricks {
    param (
        [string]$WorkspaceUrl,
        [string]$BearerToken,
        [string]$OldEmail,
        [string]$NewEmail
    )

    $headers = @{
        "Authorization" = "Bearer $BearerToken"
        "Content-Type"  = "application/json"
    }

    # Find user by old email via SCIM API
    $filter = [System.Web.HttpUtility]::UrlEncode("userName eq '$OldEmail'")
    $uri = "$WorkspaceUrl/api/2.0/preview/scim/v2/Users?filter=$filter"

    try {
        $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers

        if ($response.totalResults -eq 0) {
            Write-Warning "  User $OldEmail not found in Databricks workspace."
            return $false
        }

        $userId = $response.Resources[0].id

        # Update user email via SCIM PATCH
        $patchBody = @{
            schemas    = @("urn:ietf:params:scim:api:messages:2.0:PatchOp")
            Operations = @(
                @{
                    op    = "replace"
                    path  = "userName"
                    value = $NewEmail
                },
                @{
                    op    = "replace"
                    path  = "emails[type eq \"work\"].value"
                    value = $NewEmail
                }
            )
        } | ConvertTo-Json -Depth 5

        $patchUri = "$WorkspaceUrl/api/2.0/preview/scim/v2/Users/$userId"
        Invoke-RestMethod -Uri $patchUri -Method PATCH -Headers $headers -Body $patchBody
        Write-Host "  Updated Databricks: $OldEmail -> $NewEmail" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "  Databricks update failed for $OldEmail : $_"
        return $false
    }
}

# ============================================================
# Main
# ============================================================

Write-Host "`n=== Azure AD User Sync ===" -ForegroundColor Cyan

if (-not $UpdateAzureAD) {
    Write-Host "PREVIEW MODE - no changes will be applied. Use -UpdateAzureAD to apply.`n" -ForegroundColor Yellow
}

# Validate input file
if (-not (Test-Path $InputCsv)) {
    Write-Error "Input file not found: $InputCsv"
    exit 1
}

$users = Import-Csv $InputCsv
Write-Host "Loaded $($users.Count) user(s) from $InputCsv`n"

$successCount = 0
$failCount = 0
$skipCount = 0

foreach ($user in $users) {
    Write-Host "Processing: $($user.UserPrincipalName)" -ForegroundColor Cyan

    # Validate required fields
    if ([string]::IsNullOrWhiteSpace($user.OldEmail) -or [string]::IsNullOrWhiteSpace($user.NewEmail)) {
        Write-Warning "  Missing email fields. Skipping."
        $skipCount++
        continue
    }

    if ($UpdateAzureAD) {
        $adResult = Update-UserEmailInAD -UserPrincipalName $user.UserPrincipalName `
                                          -OldEmail $user.OldEmail -NewEmail $user.NewEmail

        if ($adResult -and $SyncToDatabricks -and $user.DatabricksWorkspace) {
            # Retrieve workspace token from Key Vault
            $tokenSecretName = "dbx-token-$($user.DatabricksWorkspace)"
            $bearerToken = Get-AzKeyVaultSecret -VaultName "kv-prod-001" -Name $tokenSecretName -AsPlainText

            if ($bearerToken) {
                $workspaceUrl = "https://$($user.DatabricksWorkspace).azuredatabricks.net"
                Update-UserEmailInDatabricks -WorkspaceUrl $workspaceUrl -BearerToken $bearerToken `
                                              -OldEmail $user.OldEmail -NewEmail $user.NewEmail
            }
            else {
                Write-Warning "  No Databricks token found for workspace: $($user.DatabricksWorkspace)"
            }
        }

        if ($adResult) { $successCount++ } else { $failCount++ }
    }
    else {
        Write-Host "  Would update: $($user.OldEmail) -> $($user.NewEmail)" -ForegroundColor DarkGray
        $skipCount++
    }
}

# Summary
Write-Host "`n=== Sync Summary ===" -ForegroundColor Cyan
Write-Host "Total users:  $($users.Count)"
Write-Host "Updated:      $successCount"
Write-Host "Failed:       $failCount"
Write-Host "Skipped:      $skipCount"
