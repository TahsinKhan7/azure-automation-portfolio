BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_TestHelper.ps1')

    $script:now = [datetime]::new(2026, 10, 15, 9, 0, 0, [System.DateTimeKind]::Utc)
    function script:ToEpochMs([datetime]$Value) { [DateTimeOffset]::new($Value).ToUnixTimeMilliseconds() }

    $script:tokens = @(
        [pscustomobject]@{ token_id = 'expiring'; comment = 'adf'; creation_time = (ToEpochMs $script:now.AddDays(-25)); expiry_time = (ToEpochMs $script:now.AddDays(3)) }
        [pscustomobject]@{ token_id = 'healthy'; comment = 'aks'; creation_time = (ToEpochMs $script:now.AddDays(-5)); expiry_time = (ToEpochMs $script:now.AddDays(25)) }
        [pscustomobject]@{ token_id = 'expired'; comment = 'old'; creation_time = (ToEpochMs $script:now.AddDays(-60)); expiry_time = (ToEpochMs $script:now.AddDays(-1)) }
        [pscustomobject]@{ token_id = 'forever'; comment = 'legacy'; creation_time = (ToEpochMs $script:now.AddDays(-400)); expiry_time = -1 }
    )
}

Describe 'Get-DpTokenRotationPlan' {
    It 'marks tokens inside the rotation window for rotation' {
        $plan = Get-DpTokenRotationPlan -Token $script:tokens -RotationWindowDays 7 -Now $script:now
        ($plan | Where-Object TokenId -EQ 'expiring').Action | Should -Be 'Rotate'
        ($plan | Where-Object TokenId -EQ 'expiring').DaysRemaining | Should -Be 3
    }

    It 'keeps tokens outside the window' {
        $plan = Get-DpTokenRotationPlan -Token $script:tokens -RotationWindowDays 7 -Now $script:now
        ($plan | Where-Object TokenId -EQ 'healthy').Action | Should -Be 'Keep'
    }

    It 'classifies already-expired tokens separately' {
        $plan = Get-DpTokenRotationPlan -Token $script:tokens -RotationWindowDays 7 -Now $script:now
        ($plan | Where-Object TokenId -EQ 'expired').Action | Should -Be 'Expired'
    }

    It 'keeps non-expiring tokens unless asked to include them' {
        (Get-DpTokenRotationPlan -Token $script:tokens -Now $script:now | Where-Object TokenId -EQ 'forever').Action | Should -Be 'Keep'
        (Get-DpTokenRotationPlan -Token $script:tokens -Now $script:now -IncludeNonExpiring | Where-Object TokenId -EQ 'forever').Action | Should -Be 'Rotate'
    }

    It 'widening the window pulls more tokens into rotation' {
        $rotate = Get-DpTokenRotationPlan -Token $script:tokens -RotationWindowDays 30 -Now $script:now | Where-Object Action -EQ 'Rotate'
        $rotate.TokenId | Should -Contain 'healthy'
    }
}

Describe 'Get-DpDatabricksAccessToken' {
    It 'returns the SecureString from Key Vault' {
        Mock -CommandName Get-AzKeyVaultSecret -ModuleName $script:ModuleName -MockWith {
            [pscustomobject]@{ Name = $Name; SecretValue = (ConvertTo-DpSecureString -Value 'dapi-mock') }
        }

        $token = Get-DpDatabricksAccessToken -KeyVaultName 'kv-dp-data-dev-01' -SecretName 'dbx-token-dev'
        $token | Should -BeOfType [securestring]
        Should -Invoke -CommandName Get-AzKeyVaultSecret -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter { $VaultName -eq 'kv-dp-data-dev-01' -and $Name -eq 'dbx-token-dev' }
    }

    It 'throws a clear error when the secret is missing' {
        Mock -CommandName Get-AzKeyVaultSecret -ModuleName $script:ModuleName -MockWith { $null }
        { Get-DpDatabricksAccessToken -KeyVaultName 'kv' -SecretName 'missing' } | Should -Throw '*not found*'
    }
}

Describe 'Invoke-DpDatabricksApi' {
    BeforeAll {
        $script:secureToken = ConvertTo-DpSecureString -Value 'dapi-mock'
    }

    It 'sends a bearer header and JSON body to the workspace URL' {
        Mock -CommandName Invoke-RestMethod -ModuleName $script:ModuleName -MockWith { [pscustomobject]@{ ok = $true } }

        Invoke-DpDatabricksApi -WorkspaceUrl 'https://adb-1.azuredatabricks.net/' -AccessToken $script:secureToken -Path '/api/2.0/token/create' -Method POST -Body @{ comment = 'x' } | Out-Null

        Should -Invoke -CommandName Invoke-RestMethod -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://adb-1.azuredatabricks.net/api/2.0/token/create' -and
            $Method -eq 'POST' -and
            $Headers.Authorization -eq 'Bearer dapi-mock' -and
            ($Body | ConvertFrom-Json).comment -eq 'x'
        }
    }

    It 'rejects a workspace URL that is not https' {
        { Invoke-DpDatabricksApi -WorkspaceUrl 'http://adb-1.azuredatabricks.net' -AccessToken $script:secureToken -Path '/api/2.0/token/list' } | Should -Throw
    }
}

Describe 'New-DpDatabricksToken' {
    It 'returns the new token value as a SecureString and honours -WhatIf' {
        Mock -CommandName Invoke-RestMethod -ModuleName $script:ModuleName -MockWith {
            [pscustomobject]@{ token_value = 'dapi-new'; token_info = [pscustomobject]@{ token_id = 'new-id'; expiry_time = 1800000000000 } }
        }
        $secure = ConvertTo-DpSecureString -Value 'dapi-mock'

        $result = New-DpDatabricksToken -WorkspaceUrl 'https://adb-1.azuredatabricks.net' -AccessToken $secure -LifetimeDays 30 -Comment 'test'
        $result.TokenId | Should -Be 'new-id'
        $result.TokenValue | Should -BeOfType [securestring]

        New-DpDatabricksToken -WorkspaceUrl 'https://adb-1.azuredatabricks.net' -AccessToken $secure -Comment 'test' -WhatIf | Should -BeNullOrEmpty
        Should -Invoke -CommandName Invoke-RestMethod -ModuleName $script:ModuleName -Times 1 -Exactly
    }
}
