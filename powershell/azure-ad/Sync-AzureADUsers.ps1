<#
.SYNOPSIS
    Bulk-updates Entra ID user email attributes and optionally mirrors the change into Databricks.

.DESCRIPTION
    Reads a CSV with UserPrincipalName, OldEmail, NewEmail and DatabricksWorkspace
    columns. Preview by default; -UpdateAzureAD applies the Entra change and
    -SyncToDatabricks patches the SCIM user in the named workspace.

.EXAMPLE
    ./Sync-AzureADUsers.ps1 -InputCsv ./users.csv -KeyVaultName kv-dp-data-prod-01 -UpdateAzureAD -SyncToDatabricks
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$InputCsv,

    [Parameter(Mandatory)]
    [string]$KeyVaultName,

    [switch]$UpdateAzureAD,

    [switch]$SyncToDatabricks
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../modules/DataPlatform.Automation/DataPlatform.Automation.psd1') -Force

function Update-DatabricksUserEmail {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param ([string]$WorkspaceUrl, [securestring]$AccessToken, [string]$OldEmail, [string]$NewEmail)

    $filter = [uri]::EscapeDataString("userName eq '$OldEmail'")
    $found = Invoke-DpDatabricksApi -WorkspaceUrl $WorkspaceUrl -AccessToken $AccessToken -Path "/api/2.0/preview/scim/v2/Users?filter=$filter"
    if ($found.totalResults -eq 0) {
        Write-DpLog -Message "  $OldEmail not found in $WorkspaceUrl" -Level Warning
        return $false
    }

    $patch = @{
        schemas    = @('urn:ietf:params:scim:api:messages:2.0:PatchOp')
        Operations = @(
            @{ op = 'replace'; path = 'userName'; value = $NewEmail },
            @{ op = 'replace'; path = 'emails[type eq "work"].value'; value = $NewEmail }
        )
    }

    if ($PSCmdlet.ShouldProcess($WorkspaceUrl, "Rename $OldEmail to $NewEmail")) {
        Invoke-DpDatabricksApi -WorkspaceUrl $WorkspaceUrl -AccessToken $AccessToken -Path "/api/2.0/preview/scim/v2/Users/$($found.Resources[0].id)" -Method PATCH -Body $patch | Out-Null
    }
    return $true
}

Write-DpLog -Message 'Entra ID user email sync'
if (-not $UpdateAzureAD) {
    Write-DpLog -Message 'Preview mode: use -UpdateAzureAD to apply.' -Level Warning
}

$users = @(Import-Csv -Path $InputCsv)
$updated = 0
$failed = 0
$skipped = 0
$tokens = @{}

foreach ($user in $users) {
    if ([string]::IsNullOrWhiteSpace($user.OldEmail) -or [string]::IsNullOrWhiteSpace($user.NewEmail)) {
        Write-DpLog -Message "Skipping $($user.UserPrincipalName): missing email fields." -Level Warning
        $skipped++
        continue
    }

    if (-not $UpdateAzureAD) {
        Write-DpLog -Message "Would update $($user.UserPrincipalName): $($user.OldEmail) -> $($user.NewEmail)"
        $skipped++
        continue
    }

    try {
        $entraUser = Get-AzADUser -UserPrincipalName $user.UserPrincipalName
        if (-not $entraUser) {
            throw 'user not found in Entra ID'
        }
        if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, "Set other mail to $($user.NewEmail)")) {
            Update-AzADUser -ObjectId $entraUser.Id -OtherMail @($user.NewEmail)
        }

        if ($SyncToDatabricks -and $user.DatabricksWorkspace) {
            if (-not $tokens.ContainsKey($user.DatabricksWorkspace)) {
                $tokens[$user.DatabricksWorkspace] = Get-DpDatabricksAccessToken -KeyVaultName $KeyVaultName -SecretName "dbx-token-$($user.DatabricksWorkspace)"
            }
            Update-DatabricksUserEmail -WorkspaceUrl "https://$($user.DatabricksWorkspace).azuredatabricks.net" -AccessToken $tokens[$user.DatabricksWorkspace] `
                -OldEmail $user.OldEmail -NewEmail $user.NewEmail | Out-Null
        }

        Write-DpLog -Message "Updated $($user.UserPrincipalName)" -Level Success
        $updated++
    } catch {
        Write-DpLog -Message "Failed $($user.UserPrincipalName): $($_.Exception.Message)" -Level Warning
        $failed++
    }
}

[pscustomobject]@{
    Total   = $users.Count
    Updated = $updated
    Failed  = $failed
    Skipped = $skipped
}
