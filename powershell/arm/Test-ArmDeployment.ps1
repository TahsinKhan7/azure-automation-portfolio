<#
.SYNOPSIS
    Validates an ARM deployment against a resource group and returns a structured result.

.DESCRIPTION
    Runs Test-AzResourceGroupDeployment for a template file or Template Spec with the
    environment parameter file, then normalises the outcome into a single object with
    IsValid, a flattened Errors collection (nested details included), timing and context.
    This is the "az deployment group validate" step of the pipeline: it catches schema,
    parameter and resource provider errors before what-if and deployment run.

.PARAMETER TemplateFile
    Local path to the ARM template. Mutually exclusive with -TemplateSpecId.

.PARAMETER TemplateSpecId
    Resource ID of a Template Spec version. Mutually exclusive with -TemplateFile.

.PARAMETER ParameterFile
    Environment parameter file.

.PARAMETER ResourceGroupName
    Target resource group. Must already exist.

.PARAMETER Environment
    Environment code: dev, ite, iqe, preprod or prod.

.PARAMETER AdditionalParameters
    Hashtable of template parameter overrides applied on top of the parameter file.

.PARAMETER OutputJsonPath
    Optional path to write the result object as JSON for later publishing.

.PARAMETER ThrowOnError
    Throw a terminating error when validation fails, which fails the pipeline task.

.EXAMPLE
    ./Test-ArmDeployment.ps1 -TemplateFile ./arm-templates/templates/main.json `
        -ParameterFile ./arm-templates/parameters/main.ite.parameters.json `
        -ResourceGroupName rg-dp-dataplatform-ite-uks -Environment ite

.EXAMPLE
    $r = ./Test-ArmDeployment.ps1 -TemplateSpecId $specId -ParameterFile $p -ResourceGroupName $rg -Environment prod
    if (-not $r.IsValid) { $r.Errors | Format-Table Code, Message }

.NOTES
    Requires Az.Resources and an authenticated Az context.
#>
[CmdletBinding()]
param (
    [Parameter()]
    [string]$TemplateFile,

    [Parameter()]
    [string]$TemplateSpecId,

    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$ParameterFile,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'ite', 'iqe', 'preprod', 'prod')]
    [string]$Environment,

    [Parameter()]
    [hashtable]$AdditionalParameters = @{},

    [Parameter()]
    [string]$OutputJsonPath,

    [Parameter()]
    [switch]$ThrowOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($TemplateFile) -eq [string]::IsNullOrWhiteSpace($TemplateSpecId)) {
    throw 'Specify exactly one of -TemplateFile or -TemplateSpecId.'
}
if ($TemplateFile -and -not (Test-Path -Path $TemplateFile -PathType Leaf)) {
    throw "Template file '$TemplateFile' was not found."
}

$inPipeline = [bool]$env:TF_BUILD

function ConvertTo-FlatErrors {
    # Test-AzResourceGroupDeployment nests root causes under Details; flatten them for reporting.
    param ($Errors, [int]$Depth = 0)
    foreach ($err in @($Errors)) {
        if ($null -eq $err) { continue }
        [PSCustomObject]@{
            Depth   = $Depth
            Code    = [string]$err.Code
            Target  = if ($err.PSObject.Properties['Target']) { [string]$err.Target } else { '' }
            Message = [string]$err.Message
        }
        if ($err.PSObject.Properties['Details'] -and $err.Details) {
            ConvertTo-FlatErrors -Errors $err.Details -Depth ($Depth + 1)
        }
    }
}

$testParams = @{
    ResourceGroupName           = $ResourceGroupName
    TemplateParameterFile       = (Resolve-Path $ParameterFile).Path
    SkipTemplateParameterPrompt = $true
}
if ($TemplateSpecId) { $testParams.TemplateSpecId = $TemplateSpecId } else { $testParams.TemplateFile = (Resolve-Path $TemplateFile).Path }
foreach ($key in $AdditionalParameters.Keys) { $testParams[$key] = $AdditionalParameters[$key] }

$templateLabel = if ($TemplateSpecId) { $TemplateSpecId } else { $TemplateFile }
Write-Host ''
Write-Host "=== Validate: $Environment ===" -ForegroundColor Cyan
Write-Host "Resource group : $ResourceGroupName"
Write-Host "Template       : $templateLabel"
Write-Host "Parameters     : $ParameterFile"

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$flatErrors = @()
try {
    $validationErrors = @(Test-AzResourceGroupDeployment @testParams)
    $flatErrors = @(ConvertTo-FlatErrors -Errors $validationErrors)
}
catch {
    # Some failures (missing template spec, unauthorised, malformed parameter file) surface as exceptions.
    $flatErrors = @([PSCustomObject]@{ Depth = 0; Code = 'ValidationException'; Target = ''; Message = $_.Exception.Message })
}
finally {
    $stopwatch.Stop()
}

$result = [PSCustomObject]@{
    Environment       = $Environment
    ResourceGroupName = $ResourceGroupName
    Template          = $templateLabel
    ParameterFile     = $ParameterFile
    IsValid           = ($flatErrors.Count -eq 0)
    ErrorCount        = $flatErrors.Count
    Errors            = $flatErrors
    DurationSeconds   = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
    TestedAtUtc       = (Get-Date).ToUniversalTime().ToString('o')
}

if ($result.IsValid) {
    Write-Host "Validation passed in $($result.DurationSeconds)s" -ForegroundColor Green
}
else {
    Write-Host "Validation failed with $($result.ErrorCount) error(s):" -ForegroundColor Red
    foreach ($err in $flatErrors) {
        $indent = '  ' * ($err.Depth + 1)
        $line = "{0}[{1}] {2}" -f $indent, $err.Code, $err.Message
        Write-Host $line -ForegroundColor Red
        if ($inPipeline -and $err.Depth -eq 0) { Write-Host "##vso[task.logissue type=error]Validation ($Environment): [$($err.Code)] $($err.Message)" }
    }
}

if ($OutputJsonPath) {
    $directory = Split-Path -Path $OutputJsonPath -Parent
    if ($directory -and -not (Test-Path $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $result | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputJsonPath -Encoding utf8
    Write-Verbose "Result written to $OutputJsonPath"
}

if ($inPipeline) {
    Write-Host "##vso[task.setvariable variable=validationPassed;isOutput=true]$($result.IsValid)"
}

$result

if (-not $result.IsValid -and $ThrowOnError) {
    throw "ARM validation failed for $Environment with $($result.ErrorCount) error(s). See log for details."
}
