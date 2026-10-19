function Test-DpTagCompliance {
    <#
    .SYNOPSIS
        Checks a tag set against the platform's mandatory tags and value rules.
    .DESCRIPTION
        Returns an object describing which required tags are missing and which
        present tags carry an invalid value (unknown environment, malformed
        cost centre). Used before creating resource groups and in audits.
    .EXAMPLE
        Test-DpTagCompliance -Tags @{ Environment = 'prod'; CostCentre = 'CC-DATA-PROD'; Owner = 'team@example.com' }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [hashtable]$Tags,

        [string[]]$RequiredTags = @('Environment', 'CostCentre', 'Owner'),

        [string[]]$AllowedEnvironments = @('dev', 'ite', 'iqe', 'preprod', 'prod'),

        [string]$CostCentrePattern = '^CC-[A-Z0-9-]+$'
    )

    $actual = if ($null -eq $Tags) { @{} } else { $Tags }

    $missing = [System.Collections.Generic.List[string]]::new()
    $invalid = @{}

    foreach ($required in $RequiredTags) {
        $present = $actual.Keys | Where-Object { $_ -ieq $required } | Select-Object -First 1
        if (-not $present -or [string]::IsNullOrWhiteSpace([string]$actual[$present])) {
            $missing.Add($required)
        }
    }

    $environmentKey = $actual.Keys | Where-Object { $_ -ieq 'Environment' } | Select-Object -First 1
    if ($environmentKey -and $actual[$environmentKey] -notin $AllowedEnvironments) {
        $invalid['Environment'] = "Value '$($actual[$environmentKey])' is not one of: $($AllowedEnvironments -join ', ')"
    }

    $costCentreKey = $actual.Keys | Where-Object { $_ -ieq 'CostCentre' } | Select-Object -First 1
    if ($costCentreKey -and -not [string]::IsNullOrWhiteSpace([string]$actual[$costCentreKey]) -and
        [string]$actual[$costCentreKey] -cnotmatch $CostCentrePattern) {
        $invalid['CostCentre'] = "Value '$($actual[$costCentreKey])' does not match $CostCentrePattern"
    }

    return [pscustomobject]@{
        IsCompliant = ($missing.Count -eq 0 -and $invalid.Count -eq 0)
        MissingTags = @($missing)
        InvalidTags = $invalid
    }
}
