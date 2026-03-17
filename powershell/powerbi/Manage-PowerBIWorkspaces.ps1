<#
.SYNOPSIS
    Manages Power BI workspaces, reports and user access via the Power BI REST API.
.DESCRIPTION
    Lists workspaces, audits user permissions, exports report metadata and manages
    workspace membership. Designed for enterprise Power BI governance.
.EXAMPLE
    .\Manage-PowerBIWorkspaces.ps1 -Action "Audit" -OutputPath ".\reports\"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("Audit", "AddUser", "RemoveUser", "ListReports")]
    [string]$Action,

    [string]$WorkspaceName,
    [string]$UserEmail,
    [string]$AccessLevel = "Member",
    [string]$OutputPath = ".\reports"
)

$ErrorActionPreference = "Stop"

# Authenticate to Power BI
Connect-PowerBIServiceAccount | Out-Null
Write-Host "`n=== Power BI Management ===" -ForegroundColor Cyan

switch ($Action) {
    "Audit" {
        Write-Host "Auditing all workspaces...`n"
        $workspaces = Get-PowerBIWorkspace -Scope Organization -All
        $report = @()

        foreach ($ws in $workspaces) {
            $users = Get-PowerBIWorkspace -Id $ws.Id -Scope Organization | Select-Object -ExpandProperty Users
            $reports = Get-PowerBIReport -WorkspaceId $ws.Id

            $report += [PSCustomObject]@{
                WorkspaceName = $ws.Name
                WorkspaceId   = $ws.Id
                State         = $ws.State
                Type          = $ws.Type
                UserCount     = ($users | Measure-Object).Count
                ReportCount   = ($reports | Measure-Object).Count
                Admins        = ($users | Where-Object { $_.AccessRight -eq "Admin" } | ForEach-Object { $_.UserPrincipalName }) -join "; "
            }
        }

        $report | Format-Table WorkspaceName, State, UserCount, ReportCount -AutoSize

        if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
        $file = Join-Path $OutputPath "pbi-workspace-audit-$(Get-Date -Format 'yyyyMMdd').csv"
        $report | Export-Csv -Path $file -NoTypeInformation
        Write-Host "`nAudit saved: $file" -ForegroundColor Green
        Write-Host "Total workspaces: $($report.Count)"
    }

    "AddUser" {
        if (-not $WorkspaceName -or -not $UserEmail) {
            Write-Error "WorkspaceName and UserEmail required for AddUser action."
            exit 1
        }
        $ws = Get-PowerBIWorkspace -Name $WorkspaceName
        Add-PowerBIWorkspaceUser -Id $ws.Id -UserPrincipalName $UserEmail -AccessRight $AccessLevel
        Write-Host "Added $UserEmail as $AccessLevel to $WorkspaceName" -ForegroundColor Green
    }

    "RemoveUser" {
        if (-not $WorkspaceName -or -not $UserEmail) {
            Write-Error "WorkspaceName and UserEmail required for RemoveUser action."
            exit 1
        }
        $ws = Get-PowerBIWorkspace -Name $WorkspaceName
        Remove-PowerBIWorkspaceUser -Id $ws.Id -UserPrincipalName $UserEmail
        Write-Host "Removed $UserEmail from $WorkspaceName" -ForegroundColor Yellow
    }

    "ListReports" {
        $ws = if ($WorkspaceName) { Get-PowerBIWorkspace -Name $WorkspaceName } else { Get-PowerBIWorkspace -Scope Organization -First 10 }
        
        foreach ($workspace in @($ws)) {
            Write-Host "`nWorkspace: $($workspace.Name)" -ForegroundColor Cyan
            $reports = Get-PowerBIReport -WorkspaceId $workspace.Id
            foreach ($r in $reports) {
                Write-Host "  $($r.Name) (Dataset: $($r.DatasetId))"
            }
        }
    }
}
