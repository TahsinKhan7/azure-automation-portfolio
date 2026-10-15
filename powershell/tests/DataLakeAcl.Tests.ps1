BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_TestHelper.ps1')

    $script:rules = @(
        [pscustomobject]@{ adGroup = 'data-engineers'; permissions = 'rwx'; paths = @('bronze', 'bronze/raw', 'silver') }
        [pscustomobject]@{ adGroup = 'data-analysts'; permissions = 'r-x'; paths = @('gold/reporting'); applyDefault = $false }
        [pscustomobject]@{ adGroup = 'unknown-group'; permissions = 'r--'; paths = @('gold') }
    )
    $script:groupIds = @{
        'data-engineers' = '11111111-1111-1111-1111-111111111111'
        'data-analysts'  = '22222222-2222-2222-2222-222222222222'
    }
}

Describe 'ConvertTo-DpDataLakeAclPlan' {
    It 'creates one entry per path for each resolvable group' {
        $plan = ConvertTo-DpDataLakeAclPlan -Rule $script:rules -GroupObjectId $script:groupIds -WarningAction SilentlyContinue
        $plan | Should -HaveCount 4
    }

    It 'skips groups that cannot be resolved and warns' {
        $plan = ConvertTo-DpDataLakeAclPlan -Rule $script:rules -GroupObjectId $script:groupIds -WarningVariable warnings -WarningAction SilentlyContinue
        $plan.GroupName | Should -Not -Contain 'unknown-group'
        $warnings | Should -Not -BeNullOrEmpty
    }

    It 'orders entries parent-first so default ACLs are set before children' {
        $plan = ConvertTo-DpDataLakeAclPlan -Rule $script:rules -GroupObjectId $script:groupIds -WarningAction SilentlyContinue
        $paths = @($plan.Path)
        $paths.IndexOf('bronze') | Should -BeLessThan $paths.IndexOf('bronze/raw')
        $paths.IndexOf('silver') | Should -BeLessThan $paths.IndexOf('gold/reporting')
    }

    It 'applies default ACLs unless the rule opts out' {
        $plan = ConvertTo-DpDataLakeAclPlan -Rule $script:rules -GroupObjectId $script:groupIds -WarningAction SilentlyContinue
        ($plan | Where-Object Path -EQ 'bronze').ApplyDefault | Should -BeTrue
        ($plan | Where-Object Path -EQ 'gold/reporting').ApplyDefault | Should -BeFalse
    }

    It 'rejects a permission string that is not a POSIX triple' {
        $bad = @([pscustomobject]@{ adGroup = 'data-engineers'; permissions = 'rw'; paths = @('bronze') })
        { ConvertTo-DpDataLakeAclPlan -Rule $bad -GroupObjectId $script:groupIds } | Should -Throw '*invalid permissions*'
    }

    It 'normalises leading and trailing slashes in paths' {
        $rule = @([pscustomobject]@{ adGroup = 'data-engineers'; permissions = 'rwx'; paths = @('/silver/cleansed/') })
        (ConvertTo-DpDataLakeAclPlan -Rule $rule -GroupObjectId $script:groupIds).Path | Should -Be 'silver/cleansed'
    }
}

Describe 'Get-DpMedallionFolderLayout' {
    It 'lists every layer before its sub-folders and includes the system folders' {
        $layout = Get-DpMedallionFolderLayout
        $layout[0] | Should -Be 'bronze'
        $layout | Should -Contain 'bronze/raw'
        $layout | Should -Contain 'gold/reporting'
        $layout | Should -Contain '_checkpoints'
        @($layout).IndexOf('silver') | Should -BeLessThan @($layout).IndexOf('silver/cleansed')
    }
}
