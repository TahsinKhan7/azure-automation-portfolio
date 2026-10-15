<#
.SYNOPSIS
Runs PSScriptAnalyzer in an isolated child process, retrying its known intermittent crashes.

.DESCRIPTION
PSScriptAnalyzer resolves command metadata from several threads at once and can fail
non-deterministically with "Object reference not set to an instance of an object" or
"The term 'Get-Command' is not recognized" (PowerShell/PSScriptAnalyzer#1351, still present
in 1.25.0). Once that happens the command cache of that process stays broken, so every
attempt here runs in a fresh pwsh process. Findings are identical on every run that
completes, so this retries the tool, never the rules: the first attempt that completes is
returned as-is, including every Error and Warning it found.

.OUTPUTS
One object per finding with ScriptPath, Line, Column, Severity, RuleName and Message.

.EXAMPLE
./scripts/ci/Invoke-ScriptAnalyzerWithRetry.ps1 -Path powershell -Settings powershell/PSScriptAnalyzerSettings.psd1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Path,

    [string] $Settings,

    # Comma-separated so it survives being passed to the worker process on the command line.
    [string] $Severity = 'Error,Warning',

    [ValidateRange(1, 10)]
    [int] $Attempts = 4,

    # Internal: run the analysis in this process and write the findings to -ResultPath.
    [switch] $AsWorker,

    [string] $ResultPath
)

$ErrorActionPreference = 'Stop'

if ($AsWorker) {
    Import-Module PSScriptAnalyzer
    $params = @{ Path = $Path; Recurse = $true; Severity = ($Severity -split ',' | ForEach-Object { $_.Trim() }) }
    if ($Settings) { $params.Settings = $Settings }
    $findings = @(Invoke-ScriptAnalyzer @params | Select-Object -Property ScriptPath, Line, Column,
        @{ Name = 'Severity'; Expression = { "$($_.Severity)" } }, RuleName, Message)
    [pscustomobject]@{ Findings = $findings } | Export-Clixml -Path $ResultPath -Depth 3
    exit 0
}

$pwsh = (Get-Process -Id $PID).Path
$findings = $null
for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    $tempResult = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("pssa-{0}.clixml" -f [guid]::NewGuid())
    $argumentList = @(
        '-NoProfile', '-NonInteractive', '-File', $PSCommandPath,
        '-AsWorker', '-ResultPath', $tempResult, '-Path', $Path, '-Severity', $Severity
    )
    if ($Settings) { $argumentList += @('-Settings', $Settings) }

    & $pwsh @argumentList
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $tempResult)) {
        $findings = @((Import-Clixml -Path $tempResult).Findings)
        Remove-Item -LiteralPath $tempResult -Force
        break
    }
    Write-Warning "PSScriptAnalyzer attempt ${attempt} of ${Attempts} did not complete (exit code ${LASTEXITCODE}); retrying in a fresh process."
}

if ($null -eq $findings) {
    throw "PSScriptAnalyzer did not complete after ${Attempts} attempts."
}
$findings
