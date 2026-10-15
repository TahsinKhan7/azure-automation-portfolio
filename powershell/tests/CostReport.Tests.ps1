BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_TestHelper.ps1')

    $script:usage = @(
        [pscustomobject]@{ InstanceId = '/subscriptions/0000/resourceGroups/rg-dp-data-prod-uks-01/providers/Microsoft.Databricks/workspaces/dbw-prod'; InstanceName = 'dbw-prod'; ConsumedService = 'Microsoft.Databricks'; PretaxCost = 120.456; Currency = 'GBP' }
        [pscustomobject]@{ InstanceId = '/subscriptions/0000/resourceGroups/rg-dp-data-prod-uks-01/providers/Microsoft.Databricks/workspaces/dbw-prod'; InstanceName = 'dbw-prod'; ConsumedService = 'Microsoft.Databricks'; PretaxCost = 79.544; Currency = 'GBP' }
        [pscustomobject]@{ InstanceId = '/subscriptions/0000/resourceGroups/rg-dp-data-prod-uks-01/providers/Microsoft.Storage/storageAccounts/stdpdataprod01'; InstanceName = 'stdpdataprod01'; ConsumedService = 'Microsoft.Storage'; PretaxCost = 15.1; Currency = 'GBP' }
        [pscustomobject]@{ InstanceId = '/subscriptions/0000/resourceGroups/rg-dp-data-dev-uks-01/providers/Microsoft.Storage/storageAccounts/stdpdatadev01'; InstanceName = 'stdpdatadev01'; ConsumedService = 'Microsoft.Storage'; PretaxCost = 2.006; Currency = 'GBP' }
    )
    $script:rows = ConvertTo-DpCostSummary -UsageDetail $script:usage -SubscriptionName 'Data Platform' -Month '2026-09'
}

Describe 'ConvertTo-DpCostSummary' {
    It 'produces one row per resource' {
        $script:rows | Should -HaveCount 3
    }

    It 'sums and rounds cost per resource to two decimal places' {
        ($script:rows | Where-Object ResourceName -EQ 'dbw-prod').TotalCost | Should -Be 200
        ($script:rows | Where-Object ResourceName -EQ 'stdpdatadev01').TotalCost | Should -Be 2.01
    }

    It 'derives the resource group from the resource ID' {
        ($script:rows | Where-Object ResourceName -EQ 'stdpdatadev01').ResourceGroup | Should -Be 'rg-dp-data-dev-uks-01'
    }

    It 'returns an empty array for no usage' {
        $empty = ConvertTo-DpCostSummary -UsageDetail @() -SubscriptionName 'x' -Month '2026-01'
        @($empty) | Should -HaveCount 0
    }

    It 'rejects a month that is not yyyy-MM' {
        { ConvertTo-DpCostSummary -UsageDetail @() -SubscriptionName 'x' -Month 'Sept 2026' } | Should -Throw
    }
}

Describe 'Get-DpCostSummaryByResourceGroup' {
    It 'rolls up to resource group with spend sorted descending' {
        $summary = Get-DpCostSummaryByResourceGroup -CostRow $script:rows
        $summary | Should -HaveCount 2
        $summary[0].ResourceGroup | Should -Be 'rg-dp-data-prod-uks-01'
        $summary[0].TotalSpend | Should -Be 215.1
        $summary[0].ResourceCount | Should -Be 2
    }
}

Describe 'Get-DpTopCostDriver' {
    It 'returns the N most expensive rows in order' {
        $top = Get-DpTopCostDriver -CostRow $script:rows -Top 2
        $top | Should -HaveCount 2
        $top[0].ResourceName | Should -Be 'dbw-prod'
        $top[1].ResourceName | Should -Be 'stdpdataprod01'
    }
}
