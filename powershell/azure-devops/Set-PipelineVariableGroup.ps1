<#
.SYNOPSIS
    Creates or updates an Azure DevOps variable group from a JSON definition, idempotently.

.DESCRIPTION
    Reads a definition file of the form
      { "name": "vg-dataplatform-dev", "variables": { "Environment": "dev", "ApiKey": { "value": "...", "isSecret": true } } }
    compares it with the live group (Compare-DpVariableGroup) and issues a
    create or update only when something differs. Secret values cannot be read
    back from the service, so existing secrets are left untouched unless
    -ForceSecretUpdate is given. Supports -WhatIf.

    Authentication: a PAT with "Variable Groups (Read, create & manage)" scope,
    or the pipeline's System.AccessToken exposed as the SYSTEM_ACCESSTOKEN
    environment variable.

.EXAMPLE
    ./Set-PipelineVariableGroup.ps1 -Organisation contoso -Project dataplatform -DefinitionFile ./config/vg-dataplatform-dev.json -WhatIf
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string]$Organisation,

    [Parameter(Mandatory)]
    [string]$Project,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$DefinitionFile,

    [securestring]$PersonalAccessToken,

    [switch]$RemoveUnmanaged,

    [switch]$ForceSecretUpdate
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../modules/DataPlatform.Automation/DataPlatform.Automation.psd1') -Force

if (-not $PersonalAccessToken) {
    if ([string]::IsNullOrEmpty($env:SYSTEM_ACCESSTOKEN)) {
        throw 'Provide -PersonalAccessToken or expose System.AccessToken as the SYSTEM_ACCESSTOKEN environment variable.'
    }
    $PersonalAccessToken = ConvertTo-DpSecureString -Value $env:SYSTEM_ACCESSTOKEN
}

$definition = Get-Content -Path $DefinitionFile -Raw | ConvertFrom-Json -AsHashtable
if (-not $definition.name -or -not $definition.variables) {
    throw "Definition file must contain 'name' and 'variables'."
}

Write-DpLog -Message "Variable group '$($definition.name)' in $Organisation/$Project"

$result = Set-DpAdoVariableGroup -Organisation $Organisation -Project $Project -Name $definition.name -Variable $definition.variables `
    -AccessToken $PersonalAccessToken -RemoveUnmanaged:$RemoveUnmanaged -ForceSecretUpdate:$ForceSecretUpdate `
    -Description ($definition.description ?? 'Managed from source control by Set-PipelineVariableGroup.ps1')

Write-DpLog -Message "Result: $($result.Action) (add $($result.ToAdd.Count), update $($result.ToUpdate.Count), remove $($result.ToRemove.Count))" -Level Success
$result
