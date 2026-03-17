<#
.SYNOPSIS
    Manages Databricks jobs via the REST API - create, list, trigger and monitor.
.EXAMPLE
    .\Manage-DatabricksJobs.ps1 -WorkspaceUrl "https://adb-xxx.azuredatabricks.net" -Action "List"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$WorkspaceUrl,
    [string]$KeyVaultName = "kv-prod-001",
    [string]$TokenSecretName = "dbx-token-prod",
    [ValidateSet("List", "Trigger", "Monitor", "Create")][string]$Action = "List",
    [string]$JobId,
    [string]$JobConfigFile
)

$ErrorActionPreference = "Stop"
$token = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $TokenSecretName -AsPlainText
$headers = @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" }

function Invoke-DBX {
    param ([string]$Path, [string]$Method = "GET", [object]$Body)
    $uri = "$WorkspaceUrl/api/2.1$Path"
    $p = @{ Uri = $uri; Method = $Method; Headers = $headers }
    if ($Body) { $p.Body = ($Body | ConvertTo-Json -Depth 10) }
    Invoke-RestMethod @p
}

Write-Host "`n=== Databricks Job Manager ===" -ForegroundColor Cyan

switch ($Action) {
    "List" {
        $jobs = (Invoke-DBX -Path "/jobs/list").jobs
        Write-Host "`nJobs ($($jobs.Count) total):"
        foreach ($j in $jobs) {
            $schedule = if ($j.settings.schedule) { $j.settings.schedule.quartz_cron_expression } else { "Manual" }
            Write-Host "  [$($j.job_id)] $($j.settings.name) | Schedule: $schedule"
        }
    }

    "Trigger" {
        if (-not $JobId) { Write-Error "JobId required for Trigger action."; exit 1 }
        $result = Invoke-DBX -Path "/jobs/run-now" -Method POST -Body @{ job_id = [int]$JobId }
        Write-Host "  Triggered job $JobId | Run ID: $($result.run_id)" -ForegroundColor Green
    }

    "Monitor" {
        $runs = (Invoke-DBX -Path "/jobs/runs/list?limit=20&active_only=false").runs
        Write-Host "`nRecent runs:"
        foreach ($run in $runs | Select-Object -First 15) {
            $status = $run.state.result_state
            $color = switch ($status) { "SUCCESS" { "Green" } "FAILED" { "Red" } default { "Yellow" } }
            $duration = if ($run.end_time -and $run.start_time) {
                [math]::Round(($run.end_time - $run.start_time) / 60000, 1)
            } else { "running" }
            Write-Host "  [$($run.run_id)] $($run.run_name) | $status | ${duration} min" -ForegroundColor $color
        }
    }

    "Create" {
        if (-not $JobConfigFile) { Write-Error "JobConfigFile required."; exit 1 }
        $jobConfig = Get-Content $JobConfigFile | ConvertFrom-Json
        $result = Invoke-DBX -Path "/jobs/create" -Method POST -Body $jobConfig
        Write-Host "  Created job ID: $($result.job_id)" -ForegroundColor Green
    }
}
