<#
.SYNOPSIS
    Audits Power BI workspaces, lists reports, and adds or removes workspace users.

.DESCRIPTION
    Formerly Manage-PowerBIWorkspaces.ps1; renamed because Manage is not an approved verb.

.EXAMPLE
    ./Set-PowerBIWorkspace.ps1 -Action Audit -OutputPath ./reports
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [ValidateSet('Audit', 'AddUser', 'RemoveUser', 'ListReports')]
    [string]$Action,

    [string]$WorkspaceName,

    [string]$UserEmail,

    [ValidateSet('Admin', 'Member', 'Contributor', 'Viewer')]
    [string]$AccessLevel = 'Member',

    [string]$OutputPath = './reports'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../modules/DataPlatform.Automation/DataPlatform.Automation.psd1') -Force

Connect-PowerBIServiceAccount | Out-Null
Write-DpLog -Message "Power BI workspaces: $Action"

switch ($Action) {
    'Audit' {
        $report = foreach ($workspace in @(Get-PowerBIWorkspace -Scope Organization -All)) {
            $users = @((Get-PowerBIWorkspace -Id $workspace.Id -Scope Organization).Users)
            $reports = @(Get-PowerBIReport -WorkspaceId $workspace.Id)
            [pscustomobject]@{
                WorkspaceName = $workspace.Name
                WorkspaceId   = $workspace.Id
                State         = $workspace.State
                Type          = $workspace.Type
                UserCount     = $users.Count
                ReportCount   = $reports.Count
                Admins        = (($users | Where-Object { $_.AccessRight -eq 'Admin' }).UserPrincipalName -join '; ')
            }
        }

        if (-not (Test-Path -Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
        $file = Join-Path -Path $OutputPath -ChildPath "pbi-workspace-audit-$(Get-Date -Format 'yyyyMMdd').csv"
        $report | Export-Csv -Path $file -NoTypeInformation
        Write-DpLog -Message "Audit saved: $file ($($report.Count) workspaces)" -Level Success
        $report
    }
    'AddUser' {
        if (-not $WorkspaceName -or -not $UserEmail) { throw 'WorkspaceName and UserEmail are required for AddUser.' }
        $workspace = Get-PowerBIWorkspace -Name $WorkspaceName
        if ($PSCmdlet.ShouldProcess($WorkspaceName, "Add $UserEmail as $AccessLevel")) {
            Add-PowerBIWorkspaceUser -Id $workspace.Id -UserPrincipalName $UserEmail -AccessRight $AccessLevel
            Write-DpLog -Message "Added $UserEmail as $AccessLevel to $WorkspaceName" -Level Success
        }
    }
    'RemoveUser' {
        if (-not $WorkspaceName -or -not $UserEmail) { throw 'WorkspaceName and UserEmail are required for RemoveUser.' }
        $workspace = Get-PowerBIWorkspace -Name $WorkspaceName
        if ($PSCmdlet.ShouldProcess($WorkspaceName, "Remove $UserEmail")) {
            Remove-PowerBIWorkspaceUser -Id $workspace.Id -UserPrincipalName $UserEmail
            Write-DpLog -Message "Removed $UserEmail from $WorkspaceName" -Level Warning
        }
    }
    'ListReports' {
        $workspaces = if ($WorkspaceName) { @(Get-PowerBIWorkspace -Name $WorkspaceName) } else { @(Get-PowerBIWorkspace -Scope Organization -First 10) }
        foreach ($workspace in $workspaces) {
            foreach ($report in @(Get-PowerBIReport -WorkspaceId $workspace.Id)) {
                [pscustomobject]@{ Workspace = $workspace.Name; Report = $report.Name; DatasetId = $report.DatasetId }
            }
        }
    }
}
