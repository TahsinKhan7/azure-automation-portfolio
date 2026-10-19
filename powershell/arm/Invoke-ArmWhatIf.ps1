<#
.SYNOPSIS
    Runs an ARM what-if analysis and produces a Markdown summary for pipeline review.

.DESCRIPTION
    Wraps Get-AzResourceGroupDeploymentWhatIfResult for either a local template file or a
    published Template Spec, using the environment parameter file. It prints the native
    what-if view, then a compact summary of Create / Modify / Delete / NoChange / Ignore
    counts, and writes a Markdown report that lists every change with property-level
    deltas for modifications.

    When executed inside Azure Pipelines the Markdown is attached to the build summary
    (##vso[task.uploadsummary]) and the delete count is exposed as an output variable
    named whatIfDeleteCount. With -FailOnDelete the script exits 1 if any resource would be
    deleted, which is the gate used for preprod and prod.

.PARAMETER TemplateFile
    Local path to the ARM template. Mutually exclusive with -TemplateSpecId.

.PARAMETER TemplateSpecId
    Resource ID of a Template Spec version. Mutually exclusive with -TemplateFile.

.PARAMETER ParameterFile
    Environment parameter file, e.g. arm-templates/parameters/main.prod.parameters.json.

.PARAMETER ResourceGroupName
    Target resource group. Must already exist.

.PARAMETER Environment
    Environment code used in the report and deployment name: dev, ite, iqe, preprod or prod.

.PARAMETER AdditionalParameters
    Hashtable of template parameter overrides applied on top of the parameter file.

.PARAMETER ResultFormat
    FullResourcePayloads (default) includes property deltas; ResourceIdOnly is faster.

.PARAMETER FailOnDelete
    Exit with code 1 when the analysis contains any Delete change.

.PARAMETER OutputPath
    Path of the Markdown report. Defaults to ./whatif-<environment>.md.

.PARAMETER DeploymentName
    Name used for the what-if deployment. Defaults to dp-<environment>-whatif-<timestamp>.

.PARAMETER PassThru
    Also return the raw what-if result object.

.EXAMPLE
    ./Invoke-ArmWhatIf.ps1 -TemplateFile ./arm-templates/templates/main.json `
        -ParameterFile ./arm-templates/parameters/main.dev.parameters.json `
        -ResourceGroupName rg-dp-dataplatform-dev-uks -Environment dev

.EXAMPLE
    ./Invoke-ArmWhatIf.ps1 -TemplateSpecId $specId -ParameterFile ./arm-templates/parameters/main.prod.parameters.json `
        -ResourceGroupName rg-dp-dataplatform-prod-uks -Environment prod -FailOnDelete -OutputPath ./whatif-prod.md

.NOTES
    Requires Az.Resources 6.x or later and an authenticated Az context.
    Exit codes: 0 success, 1 deletes detected with -FailOnDelete, 2 what-if failed.
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
    [ValidateSet('FullResourcePayloads', 'ResourceIdOnly')]
    [string]$ResultFormat = 'FullResourcePayloads',

    [Parameter()]
    [switch]$FailOnDelete,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [string]$DeploymentName,

    [Parameter()]
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($TemplateFile) -eq [string]::IsNullOrWhiteSpace($TemplateSpecId)) {
    throw 'Specify exactly one of -TemplateFile or -TemplateSpecId.'
}
if ($TemplateFile -and -not (Test-Path -Path $TemplateFile -PathType Leaf)) {
    throw "Template file '$TemplateFile' was not found."
}
if (-not $OutputPath) { $OutputPath = "./whatif-$Environment.md" }
if (-not $DeploymentName) { $DeploymentName = 'dp-{0}-whatif-{1:yyyyMMddHHmmss}' -f $Environment, (Get-Date).ToUniversalTime() }

$inPipeline = [bool]$env:TF_BUILD
$changeTypeOrder = @('Delete', 'Create', 'Modify', 'Deploy', 'NoChange', 'Ignore', 'Unsupported')

function Format-Value {
    param ($Value)
    if ($null -eq $Value) { return 'null' }
    $text = if ($Value -is [string]) { $Value } else { ConvertTo-Json -InputObject $Value -Compress -Depth 10 }
    if ($text.Length -gt 120) { $text = $text.Substring(0, 117) + '...' }
    return $text
}

function Get-PropertyChanges {
    # Flattens the nested Delta tree into "path: before -> after" rows.
    param ($Delta, [string]$Prefix = '')
    foreach ($change in @($Delta)) {
        if ($null -eq $change) { continue }
        $path = if ($Prefix) { "$Prefix.$($change.Path)" } else { $change.Path }
        if ($change.PSObject.Properties['Children'] -and $change.Children -and $change.Children.Count -gt 0) {
            Get-PropertyChanges -Delta $change.Children -Prefix $path
        }
        else {
            [PSCustomObject]@{
                Path   = $path
                Kind   = [string]$change.PropertyChangeType
                Before = Format-Value $change.Before
                After  = Format-Value $change.After
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Run what-if
# ---------------------------------------------------------------------------
$whatIfParams = @{
    Name                  = $DeploymentName
    ResourceGroupName     = $ResourceGroupName
    TemplateParameterFile = (Resolve-Path $ParameterFile).Path
    ResultFormat          = $ResultFormat
}
if ($TemplateSpecId) { $whatIfParams.TemplateSpecId = $TemplateSpecId } else { $whatIfParams.TemplateFile = (Resolve-Path $TemplateFile).Path }
foreach ($key in $AdditionalParameters.Keys) {
    # Az exposes template parameters as dynamic parameters, so overrides can be splatted directly.
    $whatIfParams[$key] = $AdditionalParameters[$key]
}

$templateLabel = if ($TemplateSpecId) { $TemplateSpecId } else { $TemplateFile }
Write-Host ''
Write-Host "=== What-if: $Environment ===" -ForegroundColor Cyan
Write-Host "Resource group : $ResourceGroupName"
Write-Host "Template       : $templateLabel"
Write-Host "Parameters     : $ParameterFile"

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $result = Get-AzResourceGroupDeploymentWhatIfResult @whatIfParams
}
catch {
    $message = "What-if failed for $Environment : $($_.Exception.Message)"
    if ($inPipeline) { Write-Host "##vso[task.logissue type=error]$message" }
    Write-Error $message
    exit 2
}
finally {
    $stopwatch.Stop()
}

if ($result.Status -ne 'Succeeded') {
    $detail = if ($result.Error) { $result.Error.Message } else { 'no detail returned' }
    $message = "What-if returned status '$($result.Status)': $detail"
    if ($inPipeline) { Write-Host "##vso[task.logissue type=error]$message" }
    Write-Error $message
    exit 2
}

# Native colourised view for the console log.
$result | Out-String -Width 220 | Write-Host

# ---------------------------------------------------------------------------
# Summarise
# ---------------------------------------------------------------------------
$changes = @($result.Changes)
$counts = [ordered]@{}
foreach ($type in $changeTypeOrder) {
    $counts[$type] = @($changes | Where-Object { [string]$_.ChangeType -eq $type }).Count
}
$deleteCount = $counts['Delete']

Write-Host 'Summary:' -ForegroundColor Cyan
foreach ($type in $changeTypeOrder) {
    if ($counts[$type] -gt 0 -or $type -in @('Create', 'Modify', 'Delete', 'NoChange')) {
        Write-Host ("  {0,-12} {1,4}" -f $type, $counts[$type])
    }
}

# ---------------------------------------------------------------------------
# Markdown report
# ---------------------------------------------------------------------------
$md = [System.Collections.Generic.List[string]]::new()
$md.Add("# What-if analysis: dataplatform $Environment")
$md.Add('')
$md.Add('| Item | Value |')
$md.Add('|------|-------|')
$md.Add("| Resource group | ``$ResourceGroupName`` |")
$md.Add("| Template | ``$templateLabel`` |")
$md.Add("| Parameter file | ``$ParameterFile`` |")
$md.Add("| Deployment name | ``$DeploymentName`` |")
$md.Add("| Generated (UTC) | $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')) |")
if ($inPipeline) { $md.Add("| Build | $($env:BUILD_DEFINITIONNAME) #$($env:BUILD_BUILDNUMBER) |") }
$md.Add("| Duration | $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s |")
$md.Add('')
$md.Add('## Summary')
$md.Add('')
$md.Add('| Change type | Count |')
$md.Add('|-------------|------:|')
foreach ($type in $changeTypeOrder) { $md.Add("| $type | $($counts[$type]) |") }
$md.Add('')
if ($deleteCount -gt 0) {
    $md.Add("> **Warning:** $deleteCount resource(s) would be deleted. Deletes require explicit sign-off before promotion.")
    $md.Add('')
}

foreach ($type in @('Delete', 'Create', 'Modify', 'Deploy', 'Unsupported')) {
    $group = @($changes | Where-Object { [string]$_.ChangeType -eq $type })
    if ($group.Count -eq 0) { continue }
    $md.Add("## $type ($($group.Count))")
    $md.Add('')
    foreach ($change in ($group | Sort-Object RelativeResourceId)) {
        $md.Add("- ``$($change.RelativeResourceId)``")
        if ($type -eq 'Modify' -and $change.PSObject.Properties['Delta'] -and $change.Delta) {
            foreach ($row in (Get-PropertyChanges -Delta $change.Delta)) {
                $md.Add("  - ``$($row.Path)`` ($($row.Kind)): ``$($row.Before)`` -> ``$($row.After)``")
            }
        }
        if ($type -eq 'Unsupported' -and $change.PSObject.Properties['UnsupportedReason']) {
            $md.Add("  - $($change.UnsupportedReason)")
        }
    }
    $md.Add('')
}

$unchanged = @($changes | Where-Object { [string]$_.ChangeType -in @('NoChange', 'Ignore') })
if ($unchanged.Count -gt 0) {
    $md.Add("<details><summary>Unchanged or ignored ($($unchanged.Count))</summary>")
    $md.Add('')
    foreach ($change in ($unchanged | Sort-Object RelativeResourceId)) {
        $md.Add("- ``$($change.RelativeResourceId)`` ($($change.ChangeType))")
    }
    $md.Add('')
    $md.Add('</details>')
    $md.Add('')
}

$md.Add('## Notes')
$md.Add('')
$md.Add('- What-if noise is expected for properties Azure normalises after deployment (for example case of resource types or default sub-properties). Review Modify entries against the intended change list before approving.')
$md.Add('- Nested deployments appear as `Deploy` entries; their child resources are listed individually.')

$directory = Split-Path -Path $OutputPath -Parent
if ($directory -and -not (Test-Path $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
Set-Content -Path $OutputPath -Value ($md -join [Environment]::NewLine) -Encoding utf8
$resolvedOutput = (Resolve-Path $OutputPath).Path
Write-Host "Markdown summary written to $resolvedOutput"

if ($inPipeline) {
    Write-Host "##vso[task.uploadsummary]$resolvedOutput"
    Write-Host "##vso[task.setvariable variable=whatIfDeleteCount;isOutput=true]$deleteCount"
    Write-Host "##vso[task.setvariable variable=whatIfCreateCount;isOutput=true]$($counts['Create'])"
    Write-Host "##vso[task.setvariable variable=whatIfModifyCount;isOutput=true]$($counts['Modify'])"
    if ($deleteCount -gt 0) {
        Write-Host "##vso[task.logissue type=warning]What-if for $Environment contains $deleteCount delete(s)."
    }
}

if ($PassThru) { $result }

if ($FailOnDelete -and $deleteCount -gt 0) {
    Write-Host "FailOnDelete is set and $deleteCount delete(s) were detected. Failing." -ForegroundColor Red
    exit 1
}
exit 0
