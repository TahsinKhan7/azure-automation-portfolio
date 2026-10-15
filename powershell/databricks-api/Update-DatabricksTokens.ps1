<#
.SYNOPSIS
    Rotates Databricks personal access tokens that are close to expiry and stores the new values in Key Vault.

.DESCRIPTION
    Formerly Rotate-DatabricksTokens.ps1; renamed because Rotate is not an
    approved verb. For each workspace in the config file: read the current
    token from Key Vault, classify existing tokens (Get-DpTokenRotationPlan),
    create a replacement, store it, then revoke the superseded tokens with the
    new credential. Token values only ever exist as SecureStrings in memory.

.EXAMPLE
    ./Update-DatabricksTokens.ps1 -KeyVaultName kv-dp-data-prod-01 -WorkspaceConfig ./config/workspaces.json -RotationWindowDays 7 -WhatIf
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string]$KeyVaultName,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$WorkspaceConfig,

    [ValidateRange(1, 365)]
    [int]$TokenLifetimeDays = 30,

    [ValidateRange(1, 90)]
    [int]$RotationWindowDays = 7
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../modules/DataPlatform.Automation/DataPlatform.Automation.psd1') -Force

Write-DpLog -Message "Databricks token rotation (lifetime $TokenLifetimeDays d, window $RotationWindowDays d)"

$workspaces = @(Get-Content -Path $WorkspaceConfig -Raw | ConvertFrom-Json)
$rotated = 0
$errors = 0

foreach ($workspace in $workspaces) {
    Write-DpLog -Message "Workspace: $($workspace.name)"
    try {
        $current = Get-DpDatabricksAccessToken -KeyVaultName $KeyVaultName -SecretName $workspace.secretName
        $tokens = Get-DpDatabricksToken -WorkspaceUrl $workspace.url -AccessToken $current
        $plan = Get-DpTokenRotationPlan -Token $tokens -RotationWindowDays $RotationWindowDays
        $due = @($plan | Where-Object { $_.Action -in @('Rotate', 'Expired') })

        if ($due.Count -eq 0) {
            Write-DpLog -Message '  No tokens due for rotation.' -Level Debug
            continue
        }

        Write-DpLog -Message "  $($due.Count) token(s) due: $($due.TokenId -join ', ')"

        if (-not $PSCmdlet.ShouldProcess($workspace.name, "Rotate $($due.Count) token(s)")) {
            continue
        }

        $replacement = New-DpDatabricksToken -WorkspaceUrl $workspace.url -AccessToken $current -LifetimeDays $TokenLifetimeDays -Comment "rotated $(Get-Date -Format 'yyyy-MM-dd') by Update-DatabricksTokens"
        Set-DpKeyVaultSecret -VaultName $KeyVaultName -Name $workspace.secretName -SecretValue $replacement.TokenValue -ContentType 'databricks-pat' -ExpiresOn $replacement.ExpiresAt

        foreach ($old in $due) {
            Revoke-DpDatabricksToken -WorkspaceUrl $workspace.url -AccessToken $replacement.TokenValue -TokenId $old.TokenId -Confirm:$false
            Write-DpLog -Message "  Revoked $($old.TokenId)" -Level Debug
        }

        $rotated++
        Write-DpLog -Message "  Rotation complete for $($workspace.name); new token expires $($replacement.ExpiresAt.ToString('u'))" -Level Success
    } catch {
        $errors++
        Write-DpLog -Message "  Failed for $($workspace.name): $($_.Exception.Message)" -Level Warning
    }
}

$summary = [pscustomobject]@{
    Workspaces = $workspaces.Count
    Rotated    = $rotated
    Errors     = $errors
}
$summary

if ($errors -gt 0) {
    throw "Token rotation completed with $errors error(s)."
}
