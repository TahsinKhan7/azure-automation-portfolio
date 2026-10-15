BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_TestHelper.ps1')

    $script:members = @(
        [pscustomobject]@{ UserPrincipalName = 'Alice@Example.com'; Id = '1'; DisplayName = 'Alice' }
        [pscustomobject]@{ UserPrincipalName = 'bob@example.com'; Id = '2'; DisplayName = 'Bob' }
        [pscustomobject]@{ UserPrincipalName = 'carol@example.com'; Id = '3'; DisplayName = 'Carol' }
        [pscustomobject]@{ UserPrincipalName = $null; Id = '4'; DisplayName = 'nested-group' }
    )
}

Describe 'Get-DpStaleGroupMember' {
    It 'returns only members absent from the authorised list' {
        $stale = Get-DpStaleGroupMember -CurrentMember $script:members -AuthorisedUserPrincipalName @('alice@example.com', 'bob@example.com')
        $stale | Should -HaveCount 1
        $stale[0].UserPrincipalName | Should -Be 'carol@example.com'
        $stale[0].Action | Should -Be 'Remove'
    }

    It 'matches user principal names case-insensitively' {
        $stale = Get-DpStaleGroupMember -CurrentMember $script:members -AuthorisedUserPrincipalName @('ALICE@EXAMPLE.COM', 'bob@example.com', 'carol@example.com')
        @($stale) | Should -HaveCount 0
    }

    It 'skips members without a user principal name instead of flagging them' {
        $stale = Get-DpStaleGroupMember -CurrentMember $script:members -AuthorisedUserPrincipalName @('alice@example.com', 'bob@example.com', 'carol@example.com')
        $stale.Id | Should -Not -Contain '4'
    }

    It 'refuses to run against an empty authorised list' {
        { Get-DpStaleGroupMember -CurrentMember $script:members -AuthorisedUserPrincipalName @() } | Should -Throw '*empty*'
    }

    It 'ignores blank entries in the authorised list but still requires at least one real entry' {
        { Get-DpStaleGroupMember -CurrentMember $script:members -AuthorisedUserPrincipalName @('', '   ') } | Should -Throw
    }

    It 'returns an empty result for an empty group' {
        @(Get-DpStaleGroupMember -CurrentMember @() -AuthorisedUserPrincipalName @('alice@example.com')) | Should -HaveCount 0
    }
}
