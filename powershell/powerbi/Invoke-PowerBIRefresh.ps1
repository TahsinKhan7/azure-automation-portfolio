<#
.SYNOPSIS
    Manages Power BI Gateway data sources and triggers dataset refreshes.
.DESCRIPTION
    Lists gateways, audits data source configurations, and triggers scheduled
    or on-demand dataset refreshes across workspaces.
.EXAMPLE
    .\Invoke-PowerBIRefresh.ps1 -WorkspaceName "Finance Reports" -DatasetName "Monthly Revenue"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)][string]$WorkspaceName,
    [Parameter(Mandatory = $false)][string]$DatasetName,
    [switch]$ListGateways,
    [switch]$RefreshAll
)

$ErrorActionPreference = "Stop"
$baseUrl = "https://api.powerbi.com/v1.0/myorg"

# Get access token
Connect-PowerBIServiceAccount | Out-Null
$token = (Get-PowerBIAccessToken -AsString).Replace("Bearer ", "")
$headers = @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" }

Write-Host "`n=== Power BI Gateway & Refresh Manager ===" -ForegroundColor Cyan

if ($ListGateways) {
    $response = Invoke-RestMethod -Uri "$baseUrl/gateways" -Headers $headers -Method GET
    Write-Host "`nGateways:" -ForegroundColor Cyan
    foreach ($gw in $response.value) {
        Write-Host "  $($gw.name) | Type: $($gw.type) | ID: $($gw.id)"
        
        # List data sources for each gateway
        $ds = Invoke-RestMethod -Uri "$baseUrl/gateways/$($gw.id)/datasources" -Headers $headers -Method GET
        foreach ($source in $ds.value) {
            Write-Host "    Source: $($source.datasourceName) | Type: $($source.datasourceType) | Status: $($source.connectionDetails)" -ForegroundColor DarkGray
        }
    }
    return
}

if ($WorkspaceName -and $DatasetName) {
    $ws = Get-PowerBIWorkspace -Name $WorkspaceName
    $dataset = Get-PowerBIDataset -WorkspaceId $ws.Id | Where-Object { $_.Name -eq $DatasetName }

    if (-not $dataset) { Write-Error "Dataset '$DatasetName' not found."; exit 1 }

    Write-Host "Triggering refresh: $DatasetName in $WorkspaceName"
    Invoke-RestMethod -Uri "$baseUrl/groups/$($ws.Id)/datasets/$($dataset.Id)/refreshes" `
                      -Headers $headers -Method POST -Body "{}"
    Write-Host "  Refresh triggered." -ForegroundColor Green
}

if ($RefreshAll -and $WorkspaceName) {
    $ws = Get-PowerBIWorkspace -Name $WorkspaceName
    $datasets = Get-PowerBIDataset -WorkspaceId $ws.Id | Where-Object { $_.IsRefreshable }

    foreach ($ds in $datasets) {
        Write-Host "  Refreshing: $($ds.Name)..." -ForegroundColor Yellow
        try {
            Invoke-RestMethod -Uri "$baseUrl/groups/$($ws.Id)/datasets/$($ds.Id)/refreshes" `
                              -Headers $headers -Method POST -Body "{}"
            Write-Host "    Triggered." -ForegroundColor Green
        }
        catch { Write-Warning "    Failed: $_" }
    }
}
