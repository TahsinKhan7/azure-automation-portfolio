<#
.SYNOPSIS
    Posts a release annotation to Application Insights so deployments appear on Azure Monitor charts.

.DESCRIPTION
    Intended to run as the last step of a deployment stage. Pipeline variables
    (Build.BuildNumber, Build.Repository.Name, Build.SourceVersion,
    Build.RequestedFor) are used as defaults when present so the step needs
    only the Application Insights resource ID and the environment.

.EXAMPLE
    ./New-ReleaseAnnotation.ps1 -ApplicationInsightsResourceId $appInsightsId -ReleaseName data-api -Environment prod -Version 1.4.0
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string]$ApplicationInsightsResourceId,

    [Parameter(Mandatory)]
    [string]$ReleaseName,

    [Parameter(Mandatory)]
    [ValidateSet('dev', 'ite', 'iqe', 'preprod', 'prod')]
    [string]$Environment,

    [string]$Version = $env:BUILD_BUILDNUMBER,

    [string]$Repository = $env:BUILD_REPOSITORY_NAME,

    [string]$Commit = $env:BUILD_SOURCEVERSION,

    [string]$RequestedBy = $env:BUILD_REQUESTEDFOR
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../modules/DataPlatform.Automation/DataPlatform.Automation.psd1') -Force

if ([string]::IsNullOrWhiteSpace($Version)) {
    throw 'Version is required (or run inside a pipeline where Build.BuildNumber is set).'
}

Write-DpLog -Message "Annotating $ReleaseName $Version -> $Environment"

$annotation = New-DpReleaseAnnotation -ApplicationInsightsResourceId $ApplicationInsightsResourceId -ReleaseName $ReleaseName -Version $Version `
    -Environment $Environment -Repository $Repository -Commit $Commit -RequestedBy $RequestedBy

if ($annotation) {
    Write-DpLog -Message "Annotation $($annotation.Id) created at $($annotation.EventTime)" -Level Success
}
$annotation
