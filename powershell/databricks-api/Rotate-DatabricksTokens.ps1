<#
.SYNOPSIS
    Automates the rotation of Databricks personal access tokens and stores them in Azure Key Vault.

.DESCRIPTION
    Connects to each specified Databricks workspace, revokes expired tokens, generates new ones
    and stores them as secrets in Azure Key Vault. Designed to replace manual token rotation
    across multiple workspaces and business units.

.PARAMETER KeyVaultName
    Name of the Azure Key Vault where tokens are stored.

.PARAMETER WorkspaceConfigs
    Path to JSON config file containing workspace URLs and service principal details.

.PARAMETER TokenLifetimeDays
    Number of days before a token is considered due for rotation. Default: 30.

.EXAMPLE
    .\Rotate-DatabricksTokens.ps1 -KeyVaultName "kv-axa-prod" -WorkspaceConfigs ".\config\workspaces.json"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceConfigs,

    [Parameter(Mandatory = $false)]
    [int]$TokenLifetimeDays = 30
)

$ErrorActionPreference = "Stop"

# ============================================================
# Functions
# ============================================================

function Get-DatabricksToken {
    param (
        [string]$WorkspaceUrl,
        [string]$BearerToken
    )

    $headers = @{
        "Authorization" = "Bearer $BearerToken"
        "Content-Type"  = "application/json"
    }

    $uri = "$WorkspaceUrl/api/2.0/token/list"
    $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers
    return $response.token_infos
}

function New-DatabricksToken {
    param (
        [string]$WorkspaceUrl,
        [string]$BearerToken,
        [int]$LifetimeSeconds,
        [string]$Comment
    )

    $headers = @{
        "Authorization" = "Bearer $BearerToken"
        "Content-Type"  = "application/json"
    }

    $body = @{
        lifetime_seconds = $LifetimeSeconds
        comment          = $Comment
    } | ConvertTo-Json

    $uri = "$WorkspaceUrl/api/2.0/token/create"
    $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body
    return $response.token_value
}

function Revoke-DatabricksToken {
    param (
        [string]$WorkspaceUrl,
        [string]$BearerToken,
        [string]$TokenId
    )

    $headers = @{
        "Authorization" = "Bearer $BearerToken"
        "Content-Type"  = "application/json"
    }

    $body = @{ token_id = $TokenId } | ConvertTo-Json
    $uri = "$WorkspaceUrl/api/2.0/token/delete"
    Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body
}

function Update-KeyVaultSecret {
    param (
        [string]$VaultName,
        [string]$SecretName,
        [string]$SecretValue
    )

    $secureValue = ConvertTo-SecureString -String $SecretValue -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -SecretValue $secureValue | Out-Null
    Write-Host "  Updated Key Vault secret: $SecretName" -ForegroundColor Green
}

# ============================================================
# Main
# ============================================================

Write-Host "`n=== Databricks Token Rotation ===" -ForegroundColor Cyan
Write-Host "Key Vault:       $KeyVaultName"
Write-Host "Config:          $WorkspaceConfigs"
Write-Host "Token Lifetime:  $TokenLifetimeDays days`n"

# Connect to Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "No Azure context found. Connecting..." -ForegroundColor Yellow
        Connect-AzAccount
    }
    Write-Host "Connected as: $($context.Account.Id)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Azure: $_"
    exit 1
}

# Load workspace configurations
if (-not (Test-Path $WorkspaceConfigs)) {
    Write-Error "Config file not found: $WorkspaceConfigs"
    exit 1
}

$workspaces = Get-Content $WorkspaceConfigs | ConvertFrom-Json
$rotatedCount = 0
$errorCount = 0

foreach ($ws in $workspaces) {
    Write-Host "`nProcessing workspace: $($ws.name)" -ForegroundColor Cyan

    try {
        # Retrieve current service principal token from Key Vault
        $currentSecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $ws.secretName -AsPlainText
        
        if (-not $currentSecret) {
            Write-Warning "  No existing secret found for $($ws.secretName). Skipping."
            continue
        }

        # List existing tokens in the workspace
        $existingTokens = Get-DatabricksToken -WorkspaceUrl $ws.url -BearerToken $currentSecret

        # Check if any tokens are approaching expiry
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $rotationThreshold = $TokenLifetimeDays * 24 * 60 * 60 * 1000

        $tokensToRotate = $existingTokens | Where-Object {
            ($_.expiry_time -gt 0) -and (($_.expiry_time - $now) -lt $rotationThreshold)
        }

        if ($tokensToRotate.Count -eq 0) {
            Write-Host "  No tokens due for rotation." -ForegroundColor Gray
            continue
        }

        Write-Host "  Found $($tokensToRotate.Count) token(s) due for rotation." -ForegroundColor Yellow

        # Generate new token
        $lifetimeSeconds = $TokenLifetimeDays * 24 * 60 * 60
        $comment = "Auto-rotated $(Get-Date -Format 'yyyy-MM-dd') by Rotate-DatabricksTokens"
        $newToken = New-DatabricksToken -WorkspaceUrl $ws.url -BearerToken $currentSecret `
                                         -LifetimeSeconds $lifetimeSeconds -Comment $comment

        # Store new token in Key Vault
        Update-KeyVaultSecret -VaultName $KeyVaultName -SecretName $ws.secretName -SecretValue $newToken

        # Revoke old tokens
        foreach ($token in $tokensToRotate) {
            Revoke-DatabricksToken -WorkspaceUrl $ws.url -BearerToken $newToken -TokenId $token.token_id
            Write-Host "  Revoked token ID: $($token.token_id)" -ForegroundColor DarkGray
        }

        $rotatedCount++
        Write-Host "  Rotation complete for $($ws.name)" -ForegroundColor Green
    }
    catch {
        $errorCount++
        Write-Error "  Failed to process $($ws.name): $_"
    }
}

# Summary
Write-Host "`n=== Rotation Summary ===" -ForegroundColor Cyan
Write-Host "Workspaces processed: $($workspaces.Count)"
Write-Host "Tokens rotated:       $rotatedCount"
Write-Host "Errors:               $errorCount"

if ($errorCount -gt 0) {
    Write-Warning "Completed with $errorCount error(s). Review output above."
    exit 1
}
else {
    Write-Host "All rotations completed successfully." -ForegroundColor Green
}
