BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_TestHelper.ps1')
    $script:pat = ConvertTo-DpSecureString -Value 'fake-pat'
}

Describe 'Compare-DpVariableGroup' {
    It 'plans a create when the group does not exist' {
        $plan = Compare-DpVariableGroup -Existing $null -Desired @{ Environment = 'dev'; LogLevel = 'DEBUG' }
        $plan.Action | Should -Be 'Create'
        $plan.ToAdd | Should -Be @('Environment', 'LogLevel')
        $plan.Variables['Environment'].value | Should -Be 'dev'
    }

    It 'reports NoChange when values already match' {
        $existing = @{ Environment = @{ value = 'dev'; isSecret = $false } }
        (Compare-DpVariableGroup -Existing $existing -Desired @{ Environment = 'dev' }).Action | Should -Be 'NoChange'
    }

    It 'plans an update for changed values and an add for new keys' {
        $existing = @{ Environment = @{ value = 'dev'; isSecret = $false } }
        $plan = Compare-DpVariableGroup -Existing $existing -Desired @{ Environment = 'ite'; Region = 'uksouth' }
        $plan.Action | Should -Be 'Update'
        $plan.ToUpdate | Should -Be @('Environment')
        $plan.ToAdd | Should -Be @('Region')
    }

    It 'leaves existing secrets alone unless forced, and never echoes a stored secret value' {
        $existing = @{ ApiKey = @{ value = $null; isSecret = $true } }
        $desired = @{ ApiKey = @{ value = 'new-secret'; isSecret = $true } }

        $plan = Compare-DpVariableGroup -Existing $existing -Desired $desired
        $plan.Action | Should -Be 'NoChange'
        $plan.Variables['ApiKey'].Keys | Should -Not -Contain 'value'

        (Compare-DpVariableGroup -Existing $existing -Desired $desired -ForceSecretUpdate).ToUpdate | Should -Be @('ApiKey')
    }

    It 'removes unmanaged variables only when asked' {
        $existing = @{ Environment = @{ value = 'dev'; isSecret = $false }; Legacy = @{ value = 'x'; isSecret = $false } }
        (Compare-DpVariableGroup -Existing $existing -Desired @{ Environment = 'dev' }).ToRemove | Should -HaveCount 0
        $plan = Compare-DpVariableGroup -Existing $existing -Desired @{ Environment = 'dev' } -RemoveUnmanaged
        $plan.ToRemove | Should -Be @('Legacy')
        $plan.Variables.Keys | Should -Not -Contain 'Legacy'
    }

    It 'compares values case-sensitively' {
        $existing = @{ Environment = @{ value = 'Dev'; isSecret = $false } }
        (Compare-DpVariableGroup -Existing $existing -Desired @{ Environment = 'dev' }).Action | Should -Be 'Update'
    }
}

Describe 'Set-DpAdoVariableGroup' {
    It 'creates the group with a POST when it does not exist' {
        Mock -CommandName Invoke-RestMethod -ModuleName $script:ModuleName -ParameterFilter { $Method -eq 'GET' } -MockWith { [pscustomobject]@{ count = 0; value = @() } }
        Mock -CommandName Invoke-RestMethod -ModuleName $script:ModuleName -ParameterFilter { $Method -eq 'POST' } -MockWith { [pscustomobject]@{ id = 42 } }

        $result = Set-DpAdoVariableGroup -Organisation 'contoso' -Project 'dataplatform' -Name 'vg-dataplatform-dev' -Variable @{ Environment = 'dev' } -AccessToken $script:pat

        $result.Action | Should -Be 'Create'
        $result.Id | Should -Be 42
        Should -Invoke -CommandName Invoke-RestMethod -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Uri -like 'https://dev.azure.com/contoso/_apis/distributedtask/variablegroups?api-version=*' -and $Headers.Authorization -like 'Basic *'
        }
    }

    It 'makes no write call when the group already matches' {
        Mock -CommandName Invoke-RestMethod -ModuleName $script:ModuleName -MockWith {
            [pscustomobject]@{ count = 1; value = @([pscustomobject]@{ id = 7; variables = [pscustomobject]@{ Environment = [pscustomobject]@{ value = 'dev'; isSecret = $false } } }) }
        }

        $result = Set-DpAdoVariableGroup -Organisation 'contoso' -Project 'dataplatform' -Name 'vg-dataplatform-dev' -Variable @{ Environment = 'dev' } -AccessToken $script:pat

        $result.Action | Should -Be 'NoChange'
        Should -Invoke -CommandName Invoke-RestMethod -ModuleName $script:ModuleName -Times 1 -Exactly
    }

    It 'issues a PUT for an update and respects -WhatIf' {
        Mock -CommandName Invoke-RestMethod -ModuleName $script:ModuleName -ParameterFilter { $Method -eq 'GET' } -MockWith {
            [pscustomobject]@{ count = 1; value = @([pscustomobject]@{ id = 7; variables = [pscustomobject]@{ Environment = [pscustomobject]@{ value = 'dev'; isSecret = $false } } }) }
        }
        Mock -CommandName Invoke-RestMethod -ModuleName $script:ModuleName -ParameterFilter { $Method -eq 'PUT' } -MockWith { $null }

        Set-DpAdoVariableGroup -Organisation 'contoso' -Project 'dataplatform' -Name 'vg-dataplatform-dev' -Variable @{ Environment = 'ite' } -AccessToken $script:pat -WhatIf | Out-Null
        Should -Invoke -CommandName Invoke-RestMethod -ModuleName $script:ModuleName -Times 0 -ParameterFilter { $Method -eq 'PUT' }

        $result = Set-DpAdoVariableGroup -Organisation 'contoso' -Project 'dataplatform' -Name 'vg-dataplatform-dev' -Variable @{ Environment = 'ite' } -AccessToken $script:pat
        $result.Action | Should -Be 'Update'
        Should -Invoke -CommandName Invoke-RestMethod -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter { $Method -eq 'PUT' -and $Uri -like '*/variablegroups/7?api-version=*' }
    }
}

Describe 'ConvertTo-DpReleaseAnnotationBody' {
    It 'produces the shape the Annotations API expects' {
        $when = [datetime]::new(2026, 10, 15, 14, 30, 0, [System.DateTimeKind]::Utc)
        $body = ConvertTo-DpReleaseAnnotationBody -ReleaseName 'data-api' -Version '1.4.0' -Environment prod -Repository 'azure-automation-portfolio' -Commit 'abc1234' -RequestedBy 'pipeline' -EventTime $when

        $body.AnnotationName | Should -Be 'data-api 1.4.0 (prod)'
        $body.Category | Should -Be 'Deployment'
        $body.EventTime | Should -Be '2026-10-15T14:30:00.000Z'
        [guid]::TryParse($body.Id, [ref]([guid]::Empty)) | Should -BeTrue
    }

    It 'serialises the metadata into the Properties JSON string' {
        $body = ConvertTo-DpReleaseAnnotationBody -ReleaseName 'data-api' -Version '1.4.0' -Environment dev -Commit 'abc1234'
        $properties = $body.Properties | ConvertFrom-Json
        $properties.Commit | Should -Be 'abc1234'
        $properties.Environment | Should -Be 'dev'
        $properties.Version | Should -Be '1.4.0'
    }

    It 'rejects an unknown environment' {
        { ConvertTo-DpReleaseAnnotationBody -ReleaseName 'x' -Version '1' -Environment staging } | Should -Throw
    }
}

Describe 'New-DpReleaseAnnotation' {
    It 'PUTs the annotation to the management API using the ARM token' {
        Mock -CommandName Get-AzAccessToken -ModuleName $script:ModuleName -MockWith { [pscustomobject]@{ Token = 'arm-token' } }
        Mock -CommandName Invoke-RestMethod -ModuleName $script:ModuleName -MockWith { [pscustomobject]@{ status = 'ok' } }
        $resourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dp-data-prod-uks-01/providers/Microsoft.Insights/components/appi-dp-data-prod'

        $result = New-DpReleaseAnnotation -ApplicationInsightsResourceId $resourceId -ReleaseName 'data-api' -Version '1.4.0' -Environment prod

        $result.AnnotationName | Should -Be 'data-api 1.4.0 (prod)'
        Should -Invoke -CommandName Invoke-RestMethod -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Uri -eq "https://management.azure.com$resourceId/Annotations?api-version=2015-05-01" -and $Headers.Authorization -eq 'Bearer arm-token'
        }
    }

    It 'does nothing under -WhatIf' {
        Mock -CommandName Get-AzAccessToken -ModuleName $script:ModuleName -MockWith { [pscustomobject]@{ Token = 'arm-token' } }
        Mock -CommandName Invoke-RestMethod -ModuleName $script:ModuleName -MockWith { $null }
        $resourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Insights/components/appi'

        New-DpReleaseAnnotation -ApplicationInsightsResourceId $resourceId -ReleaseName 'x' -Version '1' -Environment dev -WhatIf | Should -BeNullOrEmpty
        Should -Invoke -CommandName Invoke-RestMethod -ModuleName $script:ModuleName -Times 0
    }
}
