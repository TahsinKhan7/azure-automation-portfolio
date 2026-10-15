<#
.SYNOPSIS
    Lists gateways or triggers Power BI dataset refreshes.

.EXAMPLE
    ./Invoke-PowerBIRefresh.ps1 -WorkspaceName 'Finance Reports' -DatasetName 'Monthly Revenue'
.EXAMPLE
    ./Invoke-PowerBIRefresh.ps1 -WorkspaceName 'Finance Reports' -RefreshAll
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param (
    [string]$WorkspaceName,

    [string]$DatasetName,

    [switch]$ListGateways,

    [switch]$RefreshAll
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../modules/DataPlatform.Automation/DataPlatform.Automation.psd1') -Force

$baseUrl = 'https://api.powerbi.com/v1.0/myorg'
Connect-PowerBIServiceAccount | Out-Null
$headers = @{ 'Content-Type' = 'application/json' }
$headers['Authorization'] = Get-PowerBIAccessToken -AsString

Write-DpLog -Message 'Power BI gateway and refresh manager'

if ($ListGateways) {
    $gateways = (Invoke-RestMethod -Uri "$baseUrl/gateways" -Headers $headers -Method GET).value
    foreach ($gateway in $gateways) {
        $sources = (Invoke-RestMethod -Uri "$baseUrl/gateways/$($gateway.id)/datasources" -Headers $headers -Method GET).value
        [pscustomobject]@{
            Gateway     = $gateway.name
            Type        = $gateway.type
            Id          = $gateway.id
            DataSources = ($sources | ForEach-Object { "$($_.datasourceName) ($($_.datasourceType))" }) -join '; '
        }
    }
    return
}

if (-not $WorkspaceName) {
    throw 'WorkspaceName is required unless -ListGateways is used.'
}

$workspace = Get-PowerBIWorkspace -Name $WorkspaceName
$datasets = @(Get-PowerBIDataset -WorkspaceId $workspace.Id)

$targets = if ($RefreshAll) {
    $datasets | Where-Object { $_.IsRefreshable }
} else {
    $match = $datasets | Where-Object { $_.Name -eq $DatasetName }
    if (-not $match) { throw "Dataset '$DatasetName' not found in workspace '$WorkspaceName'." }
    $match
}

foreach ($dataset in $targets) {
    if ($PSCmdlet.ShouldProcess("$WorkspaceName/$($dataset.Name)", 'Trigger refresh')) {
        try {
            Invoke-RestMethod -Uri "$baseUrl/groups/$($workspace.Id)/datasets/$($dataset.Id)/refreshes" -Headers $headers -Method POST -Body '{}' | Out-Null
            Write-DpLog -Message "Refresh triggered: $($dataset.Name)" -Level Success
            [pscustomobject]@{ Workspace = $WorkspaceName; Dataset = $dataset.Name; Status = 'Triggered' }
        } catch {
            Write-DpLog -Message "Refresh failed for $($dataset.Name): $($_.Exception.Message)" -Level Warning
            [pscustomobject]@{ Workspace = $WorkspaceName; Dataset = $dataset.Name; Status = 'Failed' }
        }
    }
}
