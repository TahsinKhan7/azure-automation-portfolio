<#
.SYNOPSIS
    Provisions Entra ID group members into Databricks workspaces through the SCIM API.

.DESCRIPTION
    For each mapping (Entra group -> workspace) in the config file, adds users
    missing from the workspace. Tokens are read from Key Vault as SecureStrings
    and never written to disk or logs.

.EXAMPLE
    ./Set-DatabricksWorkspaceUsers.ps1 -ConfigFile ./config/workspace-groups.json -KeyVaultName kv-dp-data-prod-01 -WhatIf
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$ConfigFile,

    [Parameter(Mandatory)]
    [string]$KeyVaultName
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../modules/DataPlatform.Automation/DataPlatform.Automation.psd1') -Force

Write-DpLog -Message 'Databricks user provisioning'

$config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
$added = 0
$skipped = 0

foreach ($mapping in $config.mappings) {
    $workspaceUrl = "https://$($mapping.workspaceHost).azuredatabricks.net"
    Write-DpLog -Message "Workspace: $($mapping.workspaceName) | Group: $($mapping.adGroupName)"

    $token = Get-DpDatabricksAccessToken -KeyVaultName $KeyVaultName -SecretName $mapping.tokenSecretName

    $existingUsers = (Invoke-DpDatabricksApi -WorkspaceUrl $workspaceUrl -AccessToken $token -Path '/api/2.0/preview/scim/v2/Users?count=1000').Resources
    $existingEmails = [System.Collections.Generic.HashSet[string]]::new([string[]]@($existingUsers.userName), [System.StringComparer]::OrdinalIgnoreCase)

    $groupId = (Get-AzADGroup -DisplayName $mapping.adGroupName).Id
    foreach ($member in @(Get-AzADGroupMember -GroupObjectId $groupId)) {
        $email = $member.UserPrincipalName
        if ([string]::IsNullOrWhiteSpace($email) -or $existingEmails.Contains($email)) {
            $skipped++
            continue
        }

        if ($PSCmdlet.ShouldProcess($workspaceUrl, "Add user $email")) {
            $body = @{
                schemas     = @('urn:ietf:params:scim:schemas:core:2.0:User')
                userName    = $email
                displayName = $member.DisplayName
                emails      = @(@{ value = $email; type = 'work'; primary = $true })
            }
            try {
                Invoke-DpDatabricksApi -WorkspaceUrl $workspaceUrl -AccessToken $token -Path '/api/2.0/preview/scim/v2/Users' -Method POST -Body $body | Out-Null
                Write-DpLog -Message "  Added: $email" -Level Success
                $added++
            } catch {
                Write-DpLog -Message "  Failed to add $email : $($_.Exception.Message)" -Level Warning
            }
        }
    }
}

[pscustomobject]@{
    UsersAdded   = $added
    UsersSkipped = $skipped
}
