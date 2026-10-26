BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/M365Admin/M365Admin.psd1') -Force
}

Describe 'New-M365UserPrincipalName' {
    It 'builds first.last by default and lower-cases the domain' {
        New-M365UserPrincipalName -GivenName 'Jane' -Surname 'Doe' -Domain 'Contoso.COM' |
            Should -Be 'jane.doe@contoso.com'
    }

    It 'removes accents, apostrophes, hyphens and spaces' {
        $given = 'Ren' + [char]0x00E9 + 'e'
        New-M365UserPrincipalName -GivenName $given -Surname "O'Brien-Smith" -Domain 'contoso.com' |
            Should -Be 'renee.obriensmith@contoso.com'
        New-M365UserPrincipalName -GivenName 'Mary Ann' -Surname 'Van der Berg' -Domain 'contoso.com' |
            Should -Be 'maryann.vanderberg@contoso.com'
    }

    It 'supports the <Format> format' -ForEach @(
        @{ Format = 'FirstDotLast'; Expected = 'jane.doe@contoso.com' }
        @{ Format = 'FirstInitialLast'; Expected = 'jdoe@contoso.com' }
        @{ Format = 'FirstLast'; Expected = 'janedoe@contoso.com' }
    ) {
        New-M365UserPrincipalName -GivenName 'Jane' -Surname 'Doe' -Domain 'contoso.com' -Format $Format |
            Should -Be $Expected
    }

    It 'appends the next free number when names are taken (case-insensitive)' {
        New-M365UserPrincipalName -GivenName 'Jane' -Surname 'Doe' -Domain 'contoso.com' `
            -ExistingName 'JANE.DOE@contoso.com', 'jane.doe2@contoso.com' |
            Should -Be 'jane.doe3@contoso.com'
    }

    It 'asks the directory through -ExistsScript' {
        $taken = @('jane.doe@contoso.com')
        New-M365UserPrincipalName -GivenName 'Jane' -Surname 'Doe' -Domain 'contoso.com' `
            -ExistsScript { param($upn) $taken -contains $upn } |
            Should -Be 'jane.doe2@contoso.com'
    }

    It 'keeps the local part within the 64-character limit' {
        $upn = New-M365UserPrincipalName -GivenName ('a' * 40) -Surname ('b' * 40) -Domain 'contoso.com'
        $upn.Split('@')[0].Length | Should -BeLessOrEqual 64
    }

    It 'rejects names with no usable characters' {
        { New-M365UserPrincipalName -GivenName '!!!' -Surname 'Doe' -Domain 'contoso.com' } | Should -Throw '*no valid characters*'
    }

    It 'rejects an invalid domain' {
        { New-M365UserPrincipalName -GivenName 'Jane' -Surname 'Doe' -Domain 'not a domain' } | Should -Throw
    }
}

Describe 'New-M365TemporaryPassword' {
    It 'has the requested length' {
        (New-M365TemporaryPassword -Length 24).Length | Should -Be 24
        (New-M365TemporaryPassword).Length | Should -Be 16
    }

    It 'always contains upper, lower, digit and symbol characters' {
        foreach ($i in 1..50) {
            $p = New-M365TemporaryPassword -Length 14
            $p | Should -MatchExactly '[A-Z]'
            $p | Should -MatchExactly '[a-z]'
            $p | Should -Match '[0-9]'
            $p | Should -Match '[^A-Za-z0-9]'
        }
    }

    It 'never uses easily confused characters' {
        $all = -join (1..50 | ForEach-Object { New-M365TemporaryPassword -Length 32 })
        $all | Should -Not -MatchExactly '[0O1lI]'
    }

    It 'produces different passwords each time' {
        $set = 1..100 | ForEach-Object { New-M365TemporaryPassword } | Sort-Object -Unique
        @($set).Count | Should -Be 100
    }

    It 'can return a read-only SecureString' {
        $secure = New-M365TemporaryPassword -AsSecureString
        $secure | Should -BeOfType [securestring]
        $secure.IsReadOnly() | Should -BeTrue
    }

    It 'rejects lengths below 14' {
        { New-M365TemporaryPassword -Length 8 } | Should -Throw
    }
}

Describe 'Least-privilege scopes' {
    It 'requests <Expected> for <Task>' -ForEach @(
        @{ Task = 'Onboarding'; Expected = 'User.ReadWrite.All' }
        @{ Task = 'Offboarding'; Expected = 'User.RevokeSessions.All' }
        @{ Task = 'Reporting'; Expected = 'AuditLog.Read.All' }
    ) {
        InModuleScope M365Admin -Parameters @{ Task = $Task; Expected = $Expected } {
            Get-M365RequiredScope -Task $Task | Should -Contain $Expected
        }
    }

    It 'never requests write scopes for reporting' {
        InModuleScope M365Admin {
            Get-M365RequiredScope -Task Reporting | Where-Object { $_ -like '*ReadWrite*' } | Should -BeNullOrEmpty
        }
    }

    It 'combines scopes without duplicates for All' {
        InModuleScope M365Admin {
            $all = Get-M365RequiredScope -Task All
            @($all).Count | Should -Be @($all | Sort-Object -Unique).Count
            $all | Should -Contain 'Group.ReadWrite.All'
        }
    }
}
