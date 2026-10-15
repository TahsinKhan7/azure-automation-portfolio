<#
.SYNOPSIS
    Lists, triggers, monitors or creates Databricks jobs through the Jobs 2.1 API.

.DESCRIPTION
    Formerly Manage-DatabricksJobs.ps1; renamed because Manage is not an approved verb.

.EXAMPLE
    ./Invoke-DatabricksJobAction.ps1 -WorkspaceUrl https://adb-0000000000000000.0.azuredatabricks.net -KeyVaultName kv-dp-data-dev-01 -TokenSecretName dbx-token-dev -Action List
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [ValidatePattern('^https://')]
    [string]$WorkspaceUrl,

    [Parameter(Mandatory)]
    [string]$KeyVaultName,

    [Parameter(Mandatory)]
    [string]$TokenSecretName,

    [ValidateSet('List', 'Trigger', 'Monitor', 'Create')]
    [string]$Action = 'List',

    [long]$JobId,

    [string]$JobConfigFile
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../modules/DataPlatform.Automation/DataPlatform.Automation.psd1') -Force

$token = Get-DpDatabricksAccessToken -KeyVaultName $KeyVaultName -SecretName $TokenSecretName
Write-DpLog -Message "Databricks jobs: $Action"

switch ($Action) {
    'List' {
        $jobs = @((Invoke-DpDatabricksApi -WorkspaceUrl $WorkspaceUrl -AccessToken $token -Path '/api/2.1/jobs/list?limit=100').jobs)
        foreach ($job in $jobs) {
            [pscustomobject]@{
                JobId    = $job.job_id
                Name     = $job.settings.name
                Schedule = if ($job.settings.schedule) { $job.settings.schedule.quartz_cron_expression } else { 'Manual' }
                Paused   = $job.settings.schedule.pause_status -eq 'PAUSED'
            }
        }
    }
    'Trigger' {
        if (-not $JobId) { throw 'JobId is required for the Trigger action.' }
        if ($PSCmdlet.ShouldProcess($WorkspaceUrl, "Run job $JobId")) {
            $run = Invoke-DpDatabricksApi -WorkspaceUrl $WorkspaceUrl -AccessToken $token -Path '/api/2.1/jobs/run-now' -Method POST -Body @{ job_id = $JobId }
            Write-DpLog -Message "Triggered job $JobId, run $($run.run_id)" -Level Success
            [pscustomobject]@{ JobId = $JobId; RunId = $run.run_id }
        }
    }
    'Monitor' {
        $runs = @((Invoke-DpDatabricksApi -WorkspaceUrl $WorkspaceUrl -AccessToken $token -Path '/api/2.1/jobs/runs/list?limit=25').runs)
        foreach ($run in $runs) {
            [pscustomobject]@{
                RunId           = $run.run_id
                Name            = $run.run_name
                Result          = if ($run.state.result_state) { $run.state.result_state } else { $run.state.life_cycle_state }
                DurationMinutes = if ($run.end_time -and $run.start_time) { [math]::Round(($run.end_time - $run.start_time) / 60000, 1) } else { $null }
            }
        }
    }
    'Create' {
        if (-not $JobConfigFile) { throw 'JobConfigFile is required for the Create action.' }
        $definition = Get-Content -Path $JobConfigFile -Raw | ConvertFrom-Json -AsHashtable
        if ($PSCmdlet.ShouldProcess($WorkspaceUrl, "Create job '$($definition.name)'")) {
            $created = Invoke-DpDatabricksApi -WorkspaceUrl $WorkspaceUrl -AccessToken $token -Path '/api/2.1/jobs/create' -Method POST -Body $definition
            Write-DpLog -Message "Created job $($created.job_id)" -Level Success
            [pscustomobject]@{ JobId = $created.job_id; Name = $definition.name }
        }
    }
}
