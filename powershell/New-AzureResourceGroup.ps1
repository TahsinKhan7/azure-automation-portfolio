<#
.SYNOPSIS
    Creates a standardised resource group with mandatory tags, an optional lock and tag policy.

.DESCRIPTION
    Derives the resource group name from the platform naming convention
    (Get-DpResourceName), validates the tag set (Test-DpTagCompliance), then
    creates or updates the group. Production-like environments receive a
    CanNotDelete lock. Idempotent: re-running updates tags only.

.EXAMPLE
    ./New-AzureResourceGroup.ps1 -Environment prod -Workload data -CostCentre CC-DATA-PROD -OwnerEmail team@example.com
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'ite', 'iqe', 'preprod', 'prod')]
    [string]$Environment,

    [ValidatePattern('^[a-z0-9]{2,10}$')]
    [string]$Workload = 'data',

    [string]$Location = 'uksouth',

    [Parameter(Mandatory)]
    [ValidatePattern('^CC-[A-Z0-9-]+$')]
    [string]$CostCentre,

    [string]$OwnerEmail,

    [string]$Prefix = 'dp',

    [switch]$AssignTagPolicy
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'modules/DataPlatform.Automation/DataPlatform.Automation.psd1') -Force

$name = Get-DpResourceName -ResourceType ResourceGroup -Environment $Environment -Workload $Workload -Location $Location -Prefix $Prefix

$tags = @{
    Environment = $Environment
    Workload    = $Workload
    CostCentre  = $CostCentre
    Owner       = if ($OwnerEmail) { $OwnerEmail } else { (Get-AzContext).Account.Id }
    Platform    = 'dataplatform'
    ManagedBy   = 'powershell'
}

$compliance = Test-DpTagCompliance -Tags $tags
if (-not $compliance.IsCompliant) {
    throw "Tag set is not compliant. Missing: $($compliance.MissingTags -join ', '). Invalid: $(($compliance.InvalidTags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; ')"
}

Write-DpLog -Message "Resource group: $name ($Location)"

$existing = Get-AzResourceGroup -Name $name -ErrorAction SilentlyContinue
if ($existing) {
    if ($PSCmdlet.ShouldProcess($name, 'Update tags')) {
        Set-AzResourceGroup -Name $name -Tag $tags | Out-Null
        Write-DpLog -Message 'Existing group found; tags updated.' -Level Success
    }
} elseif ($PSCmdlet.ShouldProcess($name, 'Create resource group')) {
    New-AzResourceGroup -Name $name -Location $Location -Tag $tags | Out-Null
    Write-DpLog -Message 'Resource group created.' -Level Success
}

if ($Environment -in @('preprod', 'prod') -and $PSCmdlet.ShouldProcess($name, 'Apply CanNotDelete lock')) {
    New-AzResourceLock -LockName "lock-$name" -LockLevel CanNotDelete -ResourceGroupName $name -Force | Out-Null
    Write-DpLog -Message 'CanNotDelete lock applied.' -Level Success
}

if ($AssignTagPolicy) {
    $definition = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq 'Require a tag on resources' } | Select-Object -First 1
    $scope = (Get-AzResourceGroup -Name $name).ResourceId

    if ($definition -and $PSCmdlet.ShouldProcess($scope, 'Assign policy: require CostCentre tag')) {
        New-AzPolicyAssignment -Name 'require-costcentre-tag' -DisplayName 'Require CostCentre tag' -PolicyDefinition $definition `
            -Scope $scope -PolicyParameterObject @{ tagName = 'CostCentre' } | Out-Null
        Write-DpLog -Message 'Policy assignment applied.' -Level Success
    }
}

[pscustomobject]@{
    Name     = $name
    Location = $Location
    Tags     = $tags
}
