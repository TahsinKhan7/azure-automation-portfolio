BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_TestHelper.ps1')
    $script:now = [datetime]::new(2026, 10, 15, 12, 0, 0)
}

Describe 'Get-DpSecretExpiryStatus' {
    It 'returns No Expiry Set when there is no expiry date' {
        $result = Get-DpSecretExpiryStatus -Expires $null -Now $script:now
        $result.Status | Should -Be 'No Expiry Set'
        $result.DaysUntilExpiry | Should -BeNullOrEmpty
    }

    It 'returns Expired for a date in the past' {
        (Get-DpSecretExpiryStatus -Expires $script:now.AddDays(-1) -Now $script:now).Status | Should -Be 'Expired'
    }

    It 'returns Expiring Soon inside the warning window, inclusive of the boundary' {
        (Get-DpSecretExpiryStatus -Expires $script:now.AddDays(30) -WarningDays 30 -Now $script:now).Status | Should -Be 'Expiring Soon'
        (Get-DpSecretExpiryStatus -Expires $script:now.AddDays(5) -WarningDays 30 -Now $script:now).DaysUntilExpiry | Should -Be 5
    }

    It 'returns Valid outside the warning window' {
        (Get-DpSecretExpiryStatus -Expires $script:now.AddDays(31) -WarningDays 30 -Now $script:now).Status | Should -Be 'Valid'
    }
}

Describe 'Get-DpKeyVaultSecretInventory' {
    It 'lists secrets with their expiry classification using only metadata calls' {
        Mock -CommandName Get-AzKeyVaultSecret -ModuleName $script:ModuleName -ParameterFilter { -not $Name } -MockWith {
            @([pscustomobject]@{ Name = 'sql-conn' }, [pscustomobject]@{ Name = 'api-key' })
        }
        Mock -CommandName Get-AzKeyVaultSecret -ModuleName $script:ModuleName -ParameterFilter { $Name -eq 'sql-conn' } -MockWith {
            [pscustomobject]@{ Name = 'sql-conn'; Enabled = $true; Created = (Get-Date).AddDays(-100); Updated = (Get-Date).AddDays(-10); Expires = (Get-Date).AddDays(10); ContentType = 'connection-string' }
        }
        Mock -CommandName Get-AzKeyVaultSecret -ModuleName $script:ModuleName -ParameterFilter { $Name -eq 'api-key' } -MockWith {
            [pscustomobject]@{ Name = 'api-key'; Enabled = $true; Created = (Get-Date).AddDays(-400); Updated = (Get-Date).AddDays(-400); Expires = $null; ContentType = $null }
        }

        $inventory = Get-DpKeyVaultSecretInventory -VaultName 'kv-dp-data-prod-01' -WarningDays 30

        $inventory | Should -HaveCount 2
        ($inventory | Where-Object SecretName -EQ 'sql-conn').ExpiryStatus | Should -Be 'Expiring Soon'
        ($inventory | Where-Object SecretName -EQ 'api-key').ExpiryStatus | Should -Be 'No Expiry Set'
        $inventory[0].PSObject.Properties.Name | Should -Not -Contain 'SecretValue'
        Should -Invoke -CommandName Get-AzKeyVaultSecret -ModuleName $script:ModuleName -Times 3 -Exactly
    }

    It 'never requests the secret value in plain text' {
        Mock -CommandName Get-AzKeyVaultSecret -ModuleName $script:ModuleName -MockWith { @() }
        Get-DpKeyVaultSecretInventory -VaultName 'kv' | Out-Null
        Should -Invoke -CommandName Get-AzKeyVaultSecret -ModuleName $script:ModuleName -Times 0 -ParameterFilter { $AsPlainText }
    }
}
