BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_TestHelper.ps1')

    function script:New-FakeStorageAccount {
        param ([hashtable]$Overrides = @{})
        $account = [pscustomobject]@{
            StorageAccountName          = 'stdpdataprod01'
            ResourceGroupName           = 'rg-dp-data-prod-uks-01'
            PrimaryLocation             = 'uksouth'
            Kind                        = 'StorageV2'
            Sku                         = [pscustomobject]@{ Name = 'Standard_GZRS' }
            EnableHttpsTrafficOnly      = $true
            MinimumTlsVersion           = 'TLS1_2'
            AllowBlobPublicAccess       = $false
            AllowSharedKeyAccess        = $false
            EnableHierarchicalNamespace = $true
            NetworkRuleSet              = [pscustomobject]@{ DefaultAction = 'Deny' }
            Tags                        = @{ Environment = 'prod'; CostCentre = 'CC-DATA-PROD' }
        }
        foreach ($key in $Overrides.Keys) { $account.$key = $Overrides[$key] }
        return $account
    }
}

Describe 'Test-DpStorageAccountCompliance' {
    It 'passes an account that meets the full baseline' {
        $result = Test-DpStorageAccountCompliance -StorageAccount (New-FakeStorageAccount) -RequireSharedKeyDisabled -RequiredTag Environment, CostCentre
        $result.IsCompliant | Should -BeTrue
        $result.FindingCount | Should -Be 0
    }

    It 'reports TLS below 1.2' {
        $result = Test-DpStorageAccountCompliance -StorageAccount (New-FakeStorageAccount @{ MinimumTlsVersion = 'TLS1_0' })
        $result.IsCompliant | Should -BeFalse
        $result.Findings | Should -Contain "Minimum TLS version is 'TLS1_0' (expected TLS1_2)"
    }

    It 'reports anonymous blob access and an open firewall as separate findings' {
        $account = New-FakeStorageAccount @{ AllowBlobPublicAccess = $true; NetworkRuleSet = [pscustomobject]@{ DefaultAction = 'Allow' } }
        $result = Test-DpStorageAccountCompliance -StorageAccount $account
        $result.FindingCount | Should -Be 2
        $result.Findings | Should -Contain 'Anonymous blob access is allowed'
    }

    It 'only checks Shared Key when asked to' {
        $account = New-FakeStorageAccount @{ AllowSharedKeyAccess = $true }
        (Test-DpStorageAccountCompliance -StorageAccount $account).IsCompliant | Should -BeTrue
        (Test-DpStorageAccountCompliance -StorageAccount $account -RequireSharedKeyDisabled).Findings | Should -Contain 'Shared Key access is enabled'
    }

    It 'reports missing required tags' {
        $result = Test-DpStorageAccountCompliance -StorageAccount (New-FakeStorageAccount @{ Tags = @{ Environment = 'prod' } }) -RequiredTag Environment, CostCentre, Owner
        $result.Findings | Should -HaveCount 2
        $result.Findings | Should -Contain "Required tag 'Owner' is missing"
    }

    It 'treats HTTPS-only not being true as a finding' {
        (Test-DpStorageAccountCompliance -StorageAccount (New-FakeStorageAccount @{ EnableHttpsTrafficOnly = $null })).Findings | Should -Contain 'HTTPS-only traffic is not enforced'
    }
}

Describe 'Get-DpStorageAccountComplianceReport' {
    It 'audits every account returned by Get-AzStorageAccount and flattens findings' {
        Mock -CommandName Get-AzStorageAccount -ModuleName $script:ModuleName -MockWith {
            @(
                (New-FakeStorageAccount),
                (New-FakeStorageAccount @{ StorageAccountName = 'stlegacy01'; MinimumTlsVersion = 'TLS1_0'; AllowBlobPublicAccess = $true })
            )
        }

        $report = Get-DpStorageAccountComplianceReport
        $report | Should -HaveCount 2
        ($report | Where-Object Name -EQ 'stlegacy01').IsCompliant | Should -BeFalse
        ($report | Where-Object Name -EQ 'stlegacy01').Findings | Should -Match 'TLS1_0'
        ($report | Where-Object Name -EQ 'stdpdataprod01').IsCompliant | Should -BeTrue
    }

    It 'switches subscription only when one is given' {
        Mock -CommandName Get-AzStorageAccount -ModuleName $script:ModuleName -MockWith { @() }
        Mock -CommandName Set-AzContext -ModuleName $script:ModuleName -MockWith { $null }

        Get-DpStorageAccountComplianceReport | Out-Null
        Should -Invoke -CommandName Set-AzContext -ModuleName $script:ModuleName -Times 0 -Exactly

        Get-DpStorageAccountComplianceReport -SubscriptionId '00000000-0000-0000-0000-000000000000' | Out-Null
        Should -Invoke -CommandName Set-AzContext -ModuleName $script:ModuleName -Times 1 -Exactly
    }
}
