BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_TestHelper.ps1')
}

Describe 'Get-DpResourceName' {
    It 'builds a resource group name following <type>-<prefix>-<workload>-<env>-<location>-<instance>' {
        Get-DpResourceName -ResourceType ResourceGroup -Environment prod | Should -Be 'rg-dp-data-prod-uks-01'
    }

    It 'uses the compact alphanumeric form for storage accounts' {
        Get-DpResourceName -ResourceType StorageAccount -Environment dev | Should -Be 'stdpdatadev01'
    }

    It 'omits the location from Key Vault names so preprod stays within 24 characters' {
        $name = Get-DpResourceName -ResourceType KeyVault -Environment preprod
        $name | Should -Be 'kv-dp-data-preprod-01'
        $name.Length | Should -BeLessOrEqual 24
    }

    It 'uses underscores for Unity Catalog names' {
        Get-DpResourceName -ResourceType UnityCatalog -Environment iqe | Should -Be 'dp_data_iqe'
    }

    It 'falls back to the first three letters for a region without a short code' {
        Get-DpResourceName -ResourceType DataFactory -Environment ite -Location australiaeast | Should -Be 'adf-dp-data-ite-aus-01'
    }

    It 'rejects an environment outside the promotion path' {
        { Get-DpResourceName -ResourceType ResourceGroup -Environment staging } | Should -Throw
    }

    It 'throws when a storage account name would exceed 24 characters' {
        { Get-DpResourceName -ResourceType StorageAccount -Environment preprod -Workload 'warehouse1' -Prefix 'abcd' } | Should -Throw '*24*'
    }

    It 'matches the names used by the Terraform naming module for every environment' {
        foreach ($env in @('dev', 'ite', 'iqe', 'preprod', 'prod')) {
            Get-DpResourceName -ResourceType DatabricksWorkspace -Environment $env | Should -Be "dbw-dp-data-$env-uks-01"
        }
    }
}

Describe 'Test-DpTagCompliance' {
    It 'passes a complete, valid tag set' {
        $result = Test-DpTagCompliance -Tags @{ Environment = 'prod'; CostCentre = 'CC-DATA-PROD'; Owner = 'team@example.com' }
        $result.IsCompliant | Should -BeTrue
        $result.MissingTags | Should -BeNullOrEmpty
    }

    It 'lists every missing required tag' {
        $result = Test-DpTagCompliance -Tags @{ Environment = 'dev' }
        $result.IsCompliant | Should -BeFalse
        $result.MissingTags | Should -HaveCount 2
        $result.MissingTags | Should -Contain 'CostCentre'
        $result.MissingTags | Should -Contain 'Owner'
    }

    It 'treats an empty tag value as missing' {
        (Test-DpTagCompliance -Tags @{ Environment = 'dev'; CostCentre = ''; Owner = 'x' }).MissingTags | Should -Contain 'CostCentre'
    }

    It 'flags an unknown environment value' {
        $result = Test-DpTagCompliance -Tags @{ Environment = 'staging'; CostCentre = 'CC-1'; Owner = 'x' }
        $result.IsCompliant | Should -BeFalse
        $result.InvalidTags.Keys | Should -Contain 'Environment'
    }

    It 'flags a cost centre that does not match the pattern' {
        $result = Test-DpTagCompliance -Tags @{ Environment = 'dev'; CostCentre = 'finance'; Owner = 'x' }
        $result.InvalidTags['CostCentre'] | Should -Match 'does not match'
    }

    It 'handles a null tag collection without throwing' {
        $result = Test-DpTagCompliance -Tags $null
        $result.IsCompliant | Should -BeFalse
        $result.MissingTags | Should -HaveCount 3
    }
}
