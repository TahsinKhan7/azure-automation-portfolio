<#
.SYNOPSIS
    Runs the Azure Resource Manager Template Toolkit (arm-ttk) over a template folder
    and publishes the results as JUnit XML for Azure Pipelines.

.DESCRIPTION
    Resolves the arm-ttk module in this order: an explicit -ModulePath, an already
    installed module, or a shallow git clone of https://github.com/Azure/arm-ttk pinned
    to -GitRef. It then executes Test-AzTemplate against -TemplatePath, prints a results
    table grouped by file, writes a JUnit report that PublishTestResults@2 understands,
    and exits with a non-zero code when any test fails.

    Tests can be skipped with -Skip or through the "skip" array in an arm-ttk.config.json
    file next to the templates. Both lists are merged. Skips are reported so reviewers
    can see exactly which rules were exempted.

.PARAMETER TemplatePath
    Folder (or single template file) to test. Folders are tested recursively.

.PARAMETER MainTemplateFile
    Name of the orchestrator template inside the folder. arm-ttk applies a stricter rule
    set to the main template. Defaults to main.json or the value in the config file.

.PARAMETER ConfigFile
    Path to an arm-ttk.config.json. Defaults to <TemplatePath>/../arm-ttk.config.json
    when that file exists.

.PARAMETER ModulePath
    Path to an existing arm-ttk checkout (the folder that contains arm-ttk.psd1).

.PARAMETER GitRef
    Tag or branch of Azure/arm-ttk to clone when the module is not available locally.

.PARAMETER Skip
    Additional test names to skip, e.g. 'apiVersions Should Be Recent'.

.PARAMETER ResultsFile
    Where to write the JUnit XML report.

.PARAMETER FailOnWarnings
    Treat arm-ttk warnings as failures.

.PARAMETER PassThru
    Also return the raw Test-AzTemplate result objects.

.EXAMPLE
    ./Invoke-ArmTtk.ps1 -TemplatePath ./arm-templates/templates

.EXAMPLE
    ./Invoke-ArmTtk.ps1 -TemplatePath ./arm-templates/templates -Skip 'apiVersions Should Be Recent' -Verbose

.NOTES
    Requires PowerShell 7+ and git when the module needs to be cloned.
    Exit codes: 0 all tests passed, 1 one or more tests failed, 2 setup error.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -Path $_ })]
    [string]$TemplatePath,

    [Parameter()]
    [string]$MainTemplateFile,

    [Parameter()]
    [string]$ConfigFile,

    [Parameter()]
    [string]$ModulePath,

    [Parameter()]
    [string]$GitRef = 'master',

    [Parameter()]
    [string[]]$Skip = @(),

    [Parameter()]
    [string]$ResultsFile,

    [Parameter()]
    [switch]$FailOnWarnings,

    [Parameter()]
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-PipelineIssue {
    param (
        [ValidateSet('error', 'warning')] [string]$Type,
        [string]$Message
    )
    if ($env:TF_BUILD) {
        Write-Host "##vso[task.logissue type=$Type]$Message"
    }
}

function Resolve-ArmTtkModule {
    param ([string]$ExplicitPath, [string]$Ref)

    if ($ExplicitPath) {
        $manifest = Join-Path -Path $ExplicitPath -ChildPath 'arm-ttk.psd1'
        if (-not (Test-Path $manifest)) {
            $manifest = Join-Path -Path $ExplicitPath -ChildPath 'arm-ttk/arm-ttk.psd1'
        }
        if (-not (Test-Path $manifest)) { throw "arm-ttk.psd1 not found under '$ExplicitPath'." }
        return $manifest
    }

    $installed = Get-Module -ListAvailable -Name arm-ttk | Select-Object -First 1
    if ($installed) {
        Write-Verbose "Using installed arm-ttk $($installed.Version) from $($installed.ModuleBase)"
        return $installed.Path
    }

    $cacheRoot = if ($env:AGENT_TEMPDIRECTORY) { $env:AGENT_TEMPDIRECTORY } else { [System.IO.Path]::GetTempPath() }
    $cloneDir = Join-Path -Path $cacheRoot -ChildPath "arm-ttk-$Ref"
    $manifest = Join-Path -Path $cloneDir -ChildPath 'arm-ttk/arm-ttk.psd1'

    if (-not (Test-Path $manifest)) {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            throw 'arm-ttk is not installed and git is unavailable to clone it. Install git or pass -ModulePath.'
        }
        Write-Verbose "Cloning Azure/arm-ttk@$Ref into $cloneDir"
        & git clone --quiet --depth 1 --branch $Ref https://github.com/Azure/arm-ttk.git $cloneDir
        if ($LASTEXITCODE -ne 0) { throw "git clone of arm-ttk ($Ref) failed with exit code $LASTEXITCODE." }
    }
    return $manifest
}

function Read-TtkConfig {
    param ([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return $null }
    Write-Verbose "Reading arm-ttk configuration from $Path"
    return Get-Content -Path $Path -Raw | ConvertFrom-Json
}

function Get-ConfigValue {
    # Safe nested lookup that tolerates missing properties under Set-StrictMode.
    param ($Object, [string[]]$PathSegments)
    $current = $Object
    foreach ($segment in $PathSegments) {
        if ($null -eq $current -or -not $current.PSObject.Properties[$segment]) { return $null }
        $current = $current.$segment
    }
    return $current
}

function ConvertTo-JUnitXml {
    param ([object[]]$Results, [string]$Path, [timespan]$Duration)

    $escape = { param($text) [System.Security.SecurityElement]::Escape([string]$text) }
    $byFile = $Results | Group-Object { $_.File.Name }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
    $totalFailures = @($Results | Where-Object { -not $_.Passed }).Count
    [void]$sb.AppendLine(('<testsuites name="arm-ttk" tests="{0}" failures="{1}" time="{2:F3}">' -f $Results.Count, $totalFailures, $Duration.TotalSeconds))

    foreach ($group in $byFile) {
        $suiteFailures = @($group.Group | Where-Object { -not $_.Passed }).Count
        [void]$sb.AppendLine(('  <testsuite name="{0}" tests="{1}" failures="{2}">' -f (& $escape $group.Name), $group.Count, $suiteFailures))
        foreach ($result in $group.Group) {
            $caseName = & $escape $result.Name
            $className = & $escape ("arm-ttk.{0}" -f ($result.Group -replace '\s', ''))
            if ($result.Passed) {
                [void]$sb.AppendLine(('    <testcase name="{0}" classname="{1}" />' -f $caseName, $className))
            }
            else {
                $messages = @($result.Errors | ForEach-Object { $_.Exception.Message })
                if ($messages.Count -eq 0) { $messages = @($result.Warnings | ForEach-Object { $_.Message }) }
                if ($messages.Count -eq 0) { $messages = @('Test failed without a detailed message.') }
                $detail = & $escape ($messages -join [Environment]::NewLine)
                [void]$sb.AppendLine(('    <testcase name="{0}" classname="{1}">' -f $caseName, $className))
                [void]$sb.AppendLine(('      <failure message="{0}">{1}</failure>' -f (& $escape $messages[0]), $detail))
                [void]$sb.AppendLine('    </testcase>')
            }
        }
        [void]$sb.AppendLine('  </testsuite>')
    }
    [void]$sb.AppendLine('</testsuites>')

    $directory = Split-Path -Path $Path -Parent
    if ($directory -and -not (Test-Path $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    Set-Content -Path $Path -Value $sb.ToString() -Encoding utf8
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
$resolvedTemplatePath = (Resolve-Path -Path $TemplatePath).Path
if (-not $ConfigFile) {
    $candidate = Join-Path -Path (Split-Path -Path $resolvedTemplatePath -Parent) -ChildPath 'arm-ttk.config.json'
    if (Test-Path $candidate) { $ConfigFile = $candidate }
}
$config = Read-TtkConfig -Path $ConfigFile

$skipList = [System.Collections.Generic.List[string]]::new()
$skipReasons = @{}
foreach ($entry in @(Get-ConfigValue -Object $config -PathSegments @('skip'))) {
    if ($null -ne $entry) {
        $skipList.Add($entry.test)
        $skipReasons[$entry.test] = $entry.reason
    }
}
foreach ($name in ($Skip | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    if (-not $skipList.Contains($name)) { $skipList.Add($name); $skipReasons[$name] = 'Skipped via -Skip parameter' }
}

$configMainTemplate = Get-ConfigValue -Object $config -PathSegments @('armTtk', 'mainTemplateFile')
$configResultsFile = Get-ConfigValue -Object $config -PathSegments @('resultsFile')
$configGitRef = Get-ConfigValue -Object $config -PathSegments @('armTtk', 'ref')
$configFailOnWarnings = Get-ConfigValue -Object $config -PathSegments @('failOnWarnings')

if (-not $MainTemplateFile) { $MainTemplateFile = if ($configMainTemplate) { $configMainTemplate } else { 'main.json' } }
if (-not $ResultsFile) { $ResultsFile = if ($configResultsFile) { $configResultsFile } else { 'TestResults/arm-ttk-results.xml' } }
if (-not $PSBoundParameters.ContainsKey('GitRef') -and $configGitRef) { $GitRef = $configGitRef }
if (-not $FailOnWarnings -and $configFailOnWarnings -eq $true) { $FailOnWarnings = [switch]$true }

try {
    $manifest = Resolve-ArmTtkModule -ExplicitPath $ModulePath -Ref $GitRef
    Import-Module $manifest -Force
    Write-Verbose "Imported arm-ttk from $manifest"
}
catch {
    Write-PipelineIssue -Type error -Message "arm-ttk setup failed: $($_.Exception.Message)"
    Write-Error $_
    exit 2
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host "=== ARM-TTK: $resolvedTemplatePath ===" -ForegroundColor Cyan
Write-Host "Main template : $MainTemplateFile"
Write-Host "arm-ttk ref   : $GitRef"
if ($skipList.Count -gt 0) {
    Write-Host 'Skipped tests :'
    foreach ($name in $skipList) { Write-Host ("  - {0} ({1})" -f $name, $skipReasons[$name]) }
}

$testParams = @{ TemplatePath = $resolvedTemplatePath }
if ((Get-Item $resolvedTemplatePath).PSIsContainer) { $testParams.MainTemplateFile = $MainTemplateFile }
if ($skipList.Count -gt 0) { $testParams.Skip = $skipList.ToArray() }

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $results = @(Test-AzTemplate @testParams)
}
catch {
    Write-PipelineIssue -Type error -Message "Test-AzTemplate failed: $($_.Exception.Message)"
    Write-Error $_
    exit 2
}
finally {
    $stopwatch.Stop()
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
$failed = @($results | Where-Object { -not $_.Passed })
$warned = @($results | Where-Object { $_.Passed -and $_.Warnings -and $_.Warnings.Count -gt 0 })

$results |
    Sort-Object { $_.File.Name }, Passed, Name |
    Select-Object @{ n = 'File'; e = { $_.File.Name } },
                  @{ n = 'Group'; e = { $_.Group } },
                  @{ n = 'Test'; e = { $_.Name } },
                  @{ n = 'Result'; e = { if ($_.Passed) { 'Pass' } else { 'FAIL' } } } |
    Format-Table -AutoSize | Out-String -Width 200 | Write-Host

foreach ($failure in $failed) {
    foreach ($err in $failure.Errors) {
        $message = "[{0}] {1}: {2}" -f $failure.File.Name, $failure.Name, $err.Exception.Message
        Write-Host $message -ForegroundColor Red
        Write-PipelineIssue -Type error -Message $message
    }
}
foreach ($warning in $warned) {
    foreach ($w in $warning.Warnings) {
        $message = "[{0}] {1}: {2}" -f $warning.File.Name, $warning.Name, $w.Message
        Write-Host $message -ForegroundColor Yellow
        Write-PipelineIssue -Type warning -Message $message
    }
}

ConvertTo-JUnitXml -Results $results -Path $ResultsFile -Duration $stopwatch.Elapsed
Write-Host "JUnit results written to $ResultsFile"

$summary = "ARM-TTK: {0} tests, {1} failed, {2} with warnings, {3:N1}s" -f $results.Count, $failed.Count, $warned.Count, $stopwatch.Elapsed.TotalSeconds
Write-Host ''
Write-Host $summary -ForegroundColor $(if ($failed.Count -eq 0) { 'Green' } else { 'Red' })

if ($PassThru) { $results }

if ($failed.Count -gt 0 -or ($FailOnWarnings -and $warned.Count -gt 0)) {
    exit 1
}
exit 0
