<#
.SYNOPSIS
    Generates a Markdown release plan for an ARM deployment from the environment parameter
    file, git history and the release-plan template.

.DESCRIPTION
    Fills docs/release-management/release-plan-template.md with release metadata: the
    commits and files changed since -BaseRef, a table of the environment parameter values,
    the promotion order with planned dates, and optionally the what-if summary produced by
    Invoke-ArmWhatIf.ps1. The result is the document reviewers and approvers work from, and
    the pipeline publishes it as an artefact and build summary.

.PARAMETER ParameterFile
    Environment parameter file, e.g. arm-templates/parameters/main.prod.parameters.json.
    The target environment is read from its "environment" parameter.

.PARAMETER TemplatePath
    Markdown template with {{TOKEN}} placeholders. Defaults to the template in docs/release-management.

.PARAMETER OutputPath
    Where to write the plan. Defaults to ./release-plan-<environment>-<releaseId>.md.

.PARAMETER ReleaseId
    Release identifier. Defaults to the pipeline build number or a UTC timestamp.

.PARAMETER BaseRef
    Git ref the change list is computed against. Defaults to origin/main.

.PARAMETER ChangePaths
    Repository paths whose commits and files are included in the change list.

.PARAMETER EnvironmentOrder
    Promotion order. Defaults to dev, ite, iqe, preprod, prod.

.PARAMETER StartDate
    Planned date for the first environment in the order. Defaults to today.

.PARAMETER DaysBetweenEnvironments
    Working days between consecutive environments in the planned schedule.

.PARAMETER ResourceGroupName
    Target resource group. Defaults to rg-dp-dataplatform-<environment>-uks.

.PARAMETER WhatIfSummaryPath
    Optional Markdown produced by Invoke-ArmWhatIf.ps1 to embed in the plan.

.EXAMPLE
    ./New-ReleasePlan.ps1 -ParameterFile ./arm-templates/parameters/main.prod.parameters.json -ReleaseId 2026.10.15.3

.EXAMPLE
    ./New-ReleasePlan.ps1 -ParameterFile ./arm-templates/parameters/main.preprod.parameters.json `
        -WhatIfSummaryPath ./whatif-preprod.md -OutputPath ./out/release-plan.md -Verbose

.NOTES
    git is optional; when it is unavailable or the repository is shallow the plan is still
    produced with the change sections marked as unavailable.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$ParameterFile,

    [Parameter()]
    [string]$TemplatePath = (Join-Path -Path $PSScriptRoot -ChildPath '../../docs/release-management/release-plan-template.md'),

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [string]$ReleaseId,

    [Parameter()]
    [string]$BaseRef = 'origin/main',

    [Parameter()]
    [string[]]$ChangePaths = @('arm-templates', 'azure-devops-pipelines/templates', 'powershell/arm'),

    [Parameter()]
    [string[]]$EnvironmentOrder = @('dev', 'ite', 'iqe', 'preprod', 'prod'),

    [Parameter()]
    [datetime]$StartDate = (Get-Date).Date,

    [Parameter()]
    [ValidateRange(0, 30)]
    [int]$DaysBetweenEnvironments = 1,

    [Parameter()]
    [string]$ResourceGroupName,

    [Parameter()]
    [string]$WhatIfSummaryPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -Path $TemplatePath -PathType Leaf)) {
    throw "Release plan template '$TemplatePath' was not found."
}

$approvalsByEnvironment = @{
    dev     = 'Automatic on successful validation'
    ite     = 'Automatic on successful validation'
    iqe     = 'Platform lead'
    preprod = 'Platform lead + change manager'
    prod    = 'CAB record + service owner + manual what-if sign-off'
}

function Invoke-Git {
    # Returns stdout lines, or $null when git is missing or the command fails.
    param ([string[]]$Arguments)
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    try {
        $output = & git @Arguments 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return @($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    catch { return $null }
}

function Add-WorkingDays {
    param ([datetime]$Date, [int]$Days)
    $result = $Date
    while ($Days -gt 0) {
        $result = $result.AddDays(1)
        if ($result.DayOfWeek -notin @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday)) { $Days-- }
    }
    return $result
}

function Format-ParameterValue {
    param ($Spec)
    if ($Spec.PSObject.Properties['reference']) {
        return 'Key Vault reference: `{0}`' -f $Spec.reference.secretName
    }
    $value = $Spec.value
    $text = if ($value -is [string]) { $value } else { ConvertTo-Json -InputObject $value -Compress -Depth 10 }
    if ($text.Length -gt 100) { $text = $text.Substring(0, 97) + '...' }
    return '`{0}`' -f $text
}

# ---------------------------------------------------------------------------
# Gather inputs
# ---------------------------------------------------------------------------
$parameterDoc = Get-Content -Path $ParameterFile -Raw | ConvertFrom-Json
$targetEnvironment = $parameterDoc.parameters.environment.value
if (-not $targetEnvironment) { throw "Parameter file '$ParameterFile' has no 'environment' parameter." }
if ($targetEnvironment -notin $EnvironmentOrder) { throw "Environment '$targetEnvironment' is not in the promotion order ($($EnvironmentOrder -join ', '))." }

if (-not $ReleaseId) {
    $ReleaseId = if ($env:BUILD_BUILDNUMBER) { $env:BUILD_BUILDNUMBER } else { (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmm') }
}
if (-not $ResourceGroupName) { $ResourceGroupName = "rg-dp-dataplatform-$targetEnvironment-uks" }
if (-not $OutputPath) { $OutputPath = "./release-plan-$targetEnvironment-$ReleaseId.md" }

$branch = if ($env:BUILD_SOURCEBRANCHNAME) { $env:BUILD_SOURCEBRANCHNAME } else { (Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD') | Select-Object -First 1) }
$commit = if ($env:BUILD_SOURCEVERSION) { $env:BUILD_SOURCEVERSION.Substring(0, 8) } else { (Invoke-Git @('rev-parse', '--short=8', 'HEAD') | Select-Object -First 1) }
$author = if ($env:BUILD_REQUESTEDFOR) { $env:BUILD_REQUESTEDFOR } else { (Invoke-Git @('config', 'user.name') | Select-Object -First 1) }
if (-not $branch) { $branch = 'n/a' }
if (-not $commit) { $commit = 'n/a' }
if (-not $author) { $author = [Environment]::UserName }

$buildLink = if ($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI -and $env:SYSTEM_TEAMPROJECT -and $env:BUILD_BUILDID) {
    '[{0} #{1}]({2}{3}/_build/results?buildId={4})' -f $env:BUILD_DEFINITIONNAME, $env:BUILD_BUILDNUMBER, $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI, [uri]::EscapeDataString($env:SYSTEM_TEAMPROJECT), $env:BUILD_BUILDID
} else { '_local run_' }

# Change list -------------------------------------------------------------
Write-Verbose "Collecting commits $BaseRef..HEAD for $($ChangePaths -join ', ')"
$baseExists = $null -ne (Invoke-Git @('rev-parse', '--verify', '--quiet', "$BaseRef^{commit}"))
$range = if ($baseExists) { "$BaseRef..HEAD" } else { 'HEAD~20..HEAD' }
$logLines = Invoke-Git (@('log', '--no-merges', '--date=short', '--pretty=format:%h|%ad|%an|%s', $range, '--') + $ChangePaths)
$changeList = if ($null -eq $logLines) {
    '_Git history unavailable (no git or shallow clone)._'
}
elseif ($logLines.Count -eq 0) {
    "_No commits under the change paths since ``$range``._"
}
else {
    $rows = foreach ($line in $logLines) {
        $parts = $line -split '\|', 4
        '| `{0}` | {1} | {2} | {3} |' -f $parts[0], $parts[1], $parts[2], ($parts[3] -replace '\|', '\|')
    }
    (@('| Commit | Date | Author | Subject |', '|--------|------|--------|---------|') + $rows) -join "`n"
}

$diffLines = Invoke-Git (@('diff', '--name-status', $range, '--') + $ChangePaths)
$changedFiles = if ($null -eq $diffLines) {
    '_Git diff unavailable._'
}
elseif ($diffLines.Count -eq 0) {
    '_No files changed under the change paths._'
}
else {
    $statusNames = @{ A = 'Added'; M = 'Modified'; D = 'Deleted'; R = 'Renamed' }
    $rows = foreach ($line in $diffLines) {
        $parts = $line -split "`t"
        $status = $statusNames[$parts[0].Substring(0, 1)]
        if (-not $status) { $status = $parts[0] }
        '| {0} | `{1}` |' -f $status, $parts[-1]
    }
    (@('| Change | File |', '|--------|------|') + $rows) -join "`n"
}

# Parameter summary ---------------------------------------------------------
$parameterRows = foreach ($property in $parameterDoc.parameters.PSObject.Properties) {
    '| `{0}` | {1} |' -f $property.Name, (Format-ParameterValue -Spec $property.Value)
}
$parameterSummary = (@('| Parameter | Value |', '|-----------|-------|') + $parameterRows) -join "`n"

# Environment order ---------------------------------------------------------
$targetIndex = [array]::IndexOf($EnvironmentOrder, $targetEnvironment)
$orderRows = for ($i = 0; $i -lt $EnvironmentOrder.Count; $i++) {
    $envName = $EnvironmentOrder[$i]
    $planned = Add-WorkingDays -Date $StartDate -Days ($i * $DaysBetweenEnvironments)
    $status = if ($i -lt $targetIndex) { 'Prerequisite (must be deployed first)' } elseif ($i -eq $targetIndex) { '**This release**' } else { 'Later promotion' }
    $approval = if ($approvalsByEnvironment.ContainsKey($envName)) { $approvalsByEnvironment[$envName] } else { 'See environment matrix' }
    $statusText = "$status - $approval"
    '| {0} | {1} | {2:yyyy-MM-dd (ddd)} | {3} |' -f ($i + 1), $envName, $planned, $statusText
}
$environmentOrder = (@('| # | Environment | Planned date | Status / approval |', '|---|-------------|--------------|-------------------|') + $orderRows) -join "`n"

# What-if ---------------------------------------------------------------------
$whatIfSection = ''
if ($WhatIfSummaryPath) {
    if (Test-Path -Path $WhatIfSummaryPath -PathType Leaf) {
        $whatIfBody = (Get-Content -Path $WhatIfSummaryPath -Raw) -replace '(?m)^#', '###'
        $whatIfSection = "## 10. What-if summary`n`n$whatIfBody"
    }
    else {
        Write-Warning "What-if summary '$WhatIfSummaryPath' not found; section omitted."
    }
}

# ---------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------
$tokens = @{
    '{{RELEASE_ID}}'         = $ReleaseId
    '{{TARGET_ENVIRONMENT}}' = $targetEnvironment
    '{{RESOURCE_GROUP}}'     = $ResourceGroupName
    '{{PARAMETER_FILE}}'     = ($ParameterFile -replace '\\', '/')
    '{{BRANCH}}'             = $branch
    '{{COMMIT}}'             = $commit
    '{{BASE_REF}}'           = $BaseRef
    '{{BUILD_LINK}}'         = $buildLink
    '{{GENERATED_AT}}'       = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')
    '{{GENERATED_BY}}'       = $author
    '{{CHANGE_LIST}}'        = $changeList
    '{{CHANGED_FILES}}'      = $changedFiles
    '{{PARAMETER_SUMMARY}}'  = $parameterSummary
    '{{ENVIRONMENT_ORDER}}'  = $environmentOrder
    '{{WHATIF_SUMMARY}}'     = $whatIfSection
}

$content = Get-Content -Path $TemplatePath -Raw
foreach ($token in $tokens.Keys) {
    $content = $content.Replace($token, [string]$tokens[$token])
}

$unreplaced = [regex]::Matches($content, '\{\{[A-Z_]+\}\}') | ForEach-Object { $_.Value } | Sort-Object -Unique
if ($unreplaced) { Write-Warning "Unreplaced tokens in template: $($unreplaced -join ', ')" }

$directory = Split-Path -Path $OutputPath -Parent
if ($directory -and -not (Test-Path $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
Set-Content -Path $OutputPath -Value $content -Encoding utf8
$resolvedOutput = (Resolve-Path $OutputPath).Path
Write-Host "Release plan for $targetEnvironment ($ReleaseId) written to $resolvedOutput" -ForegroundColor Green

if ($env:TF_BUILD) {
    Write-Host "##vso[task.uploadsummary]$resolvedOutput"
}

[PSCustomObject]@{
    ReleaseId   = $ReleaseId
    Environment = $targetEnvironment
    OutputPath  = $resolvedOutput
    Commits     = if ($logLines) { $logLines.Count } else { 0 }
}
