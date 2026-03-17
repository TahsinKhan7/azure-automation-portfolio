<#
.SYNOPSIS
    Creates standardised Azure resource groups with mandatory tagging and policy assignments.

.DESCRIPTION
    Provisions resource groups following enterprise naming conventions and applies
    required tags (cost centre, environment, owner, project). Optionally assigns
    Azure Policy initiatives for governance compliance.

.PARAMETER Environment
    Target environment: dev, staging, prod.

.PARAMETER BusinessUnit
    Business unit code (e.g. insurance, health, uk).

.PARAMETER ProjectName
    Short project identifier for naming and tagging.

.PARAMETER Location
    Azure region. Default: uksouth.

.EXAMPLE
    .\New-AzureResourceGroup.ps1 -Environment prod -BusinessUnit insurance -ProjectName "databricks-etl"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [string]$BusinessUnit,

    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [Parameter(Mandatory = $false)]
    [string]$Location = "uksouth",

    [Parameter(Mandatory = $false)]
    [string]$CostCentre = "CC-DEFAULT",

    [Parameter(Mandatory = $false)]
    [string]$OwnerEmail
)

$ErrorActionPreference = "Stop"

# Naming convention: rg-{businessunit}-{project}-{environment}
$rgName = "rg-$BusinessUnit-$ProjectName-$Environment".ToLower()

$tags = @{
    Environment  = $Environment
    BusinessUnit = $BusinessUnit
    Project      = $ProjectName
    CostCentre   = $CostCentre
    Owner        = if ($OwnerEmail) { $OwnerEmail } else { (Get-AzContext).Account.Id }
    CreatedBy    = "Automation"
    CreatedDate  = (Get-Date -Format "yyyy-MM-dd")
}

Write-Host "`n=== Resource Group Provisioning ===" -ForegroundColor Cyan
Write-Host "Name:         $rgName"
Write-Host "Location:     $Location"
Write-Host "Environment:  $Environment"
Write-Host "Business Unit: $BusinessUnit"
Write-Host "Tags:"
$tags.GetEnumerator() | ForEach-Object { Write-Host "  $($_.Key): $($_.Value)" }

# Check if resource group already exists
$existing = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "`nResource group '$rgName' already exists. Updating tags..." -ForegroundColor Yellow
    Set-AzResourceGroup -Name $rgName -Tag $tags | Out-Null
    Write-Host "Tags updated." -ForegroundColor Green
}
else {
    Write-Host "`nCreating resource group..." -ForegroundColor Yellow
    New-AzResourceGroup -Name $rgName -Location $Location -Tag $tags | Out-Null
    Write-Host "Resource group '$rgName' created." -ForegroundColor Green
}

# Apply resource lock for production
if ($Environment -eq "prod") {
    Write-Host "Applying CanNotDelete lock for production..." -ForegroundColor Yellow
    New-AzResourceLock -LockName "DoNotDelete" -LockLevel CanNotDelete `
                        -ResourceGroupName $rgName -Force | Out-Null
    Write-Host "Lock applied." -ForegroundColor Green
}

# Assign built-in Azure Policy for tag governance
$policyDefinition = Get-AzPolicyDefinition | Where-Object {
    $_.Properties.DisplayName -eq "Require a tag on resource groups"
} | Select-Object -First 1

if ($policyDefinition) {
    $rgScope = (Get-AzResourceGroup -Name $rgName).ResourceId
    $params = @{ tagName = @{ value = "CostCentre" } }

    New-AzPolicyAssignment -Name "require-costcentre-tag" `
                            -DisplayName "Require CostCentre tag" `
                            -PolicyDefinition $policyDefinition `
                            -Scope $rgScope `
                            -PolicyParameterObject $params `
                            -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Policy assignment applied: Require CostCentre tag" -ForegroundColor Green
}

Write-Host "`nDone. Resource group '$rgName' is ready.`n" -ForegroundColor Cyan
