BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/M365Admin/M365Admin.psd1') -Force

    $script:E3 = [guid]'6fd2c87f-b296-42f0-b197-1e91e994b900'

    function Get-TestHire {
        param(
            [string]$GivenName = 'Jane',
            [string]$Surname = 'Doe',
            [string]$UsageLocation = 'CA',
            [string]$LicenseSku = 'ENTERPRISEPACK',
            [string]$Groups = 'Sales',
            [string]$Manager = 'boss@contoso.com'
        )
        [pscustomobject]@{
            GivenName     = $GivenName
            Surname       = $Surname
            Department    = 'Sales'
            JobTitle      = 'Account Executive'
            UsageLocation = $UsageLocation
            LicenseSku    = $LicenseSku
            Groups        = $Groups
            Manager       = $Manager
        }
    }
}

Describe 'New-M365Onboarding' {
    BeforeEach {
        $script:Audit = Join-Path $TestDrive "audit-$([guid]::NewGuid()).csv"
        $script:Available = 5

        Mock Test-M365GraphUser -ModuleName M365Admin { $false }
        Mock New-M365GraphUser -ModuleName M365Admin { [pscustomobject]@{ Id = 'user-1' } }
        Mock Get-M365GraphSubscribedSku -ModuleName M365Admin {
            [pscustomobject]@{
                SkuId         = $script:E3
                SkuPartNumber = 'ENTERPRISEPACK'
                ConsumedUnits = 100 - $script:Available
                PrepaidUnits  = [pscustomobject]@{ Enabled = 100; Suspended = 0; Warning = 0 }
            }
        }
        Mock Set-M365GraphUserLicense -ModuleName M365Admin { }
        Mock Get-M365GraphGroupByName -ModuleName M365Admin { [pscustomobject]@{ Id = "group-$DisplayName" } }
        Mock Add-M365GraphGroupMember -ModuleName M365Admin { }
        Mock Get-M365GraphUser -ModuleName M365Admin { [pscustomobject]@{ Id = 'manager-1' } }
        Mock Set-M365GraphUserManager -ModuleName M365Admin { }
    }

    It 'makes no changes with -WhatIf' {
        $result = Get-TestHire | New-M365Onboarding -Domain 'contoso.com' -AuditLogPath $script:Audit -WhatIf

        $result.Status | Should -Be 'WhatIf'
        $result.UserPrincipalName | Should -Be 'jane.doe@contoso.com'
        Should -Invoke New-M365GraphUser -ModuleName M365Admin -Times 0 -Exactly
        Should -Invoke Set-M365GraphUserLicense -ModuleName M365Admin -Times 0 -Exactly
        (Import-Csv $script:Audit).Result | Should -Be 'WhatIf'
    }

    It 'creates the user with a forced password change and the right attributes' {
        $result = Get-TestHire | New-M365Onboarding -Domain 'contoso.com' -AuditLogPath $script:Audit

        $result.Status | Should -Be 'Completed'
        Should -Invoke New-M365GraphUser -ModuleName M365Admin -Times 1 -Exactly -ParameterFilter {
            $Body.UserPrincipalName -eq 'jane.doe@contoso.com' -and
            $Body.MailNickname -eq 'jane.doe' -and
            $Body.DisplayName -eq 'Jane Doe' -and
            $Body.UsageLocation -eq 'CA' -and
            $Body.Department -eq 'Sales' -and
            $Body.AccountEnabled -eq $true -and
            $Body.PasswordProfile.ForceChangePasswordNextSignIn -eq $true -and
            $Body.PasswordProfile.Password.Length -ge 14
        }
    }

    It 'assigns the licence, groups and manager' {
        $result = Get-TestHire -Groups 'Sales; Canada Staff' | New-M365Onboarding -Domain 'contoso.com' -AuditLogPath $script:Audit

        $result.License | Should -Be 'ENTERPRISEPACK'
        $result.GroupsAdded | Should -Be @('Sales', 'Canada Staff')
        Should -Invoke Set-M365GraphUserLicense -ModuleName M365Admin -Times 1 -Exactly -ParameterFilter {
            $UserId -eq 'user-1' -and $AddSkuId -contains $script:E3
        }
        Should -Invoke Add-M365GraphGroupMember -ModuleName M365Admin -Times 2 -Exactly
        Should -Invoke Set-M365GraphUserManager -ModuleName M365Admin -Times 1 -Exactly -ParameterFilter {
            $UserId -eq 'user-1' -and $ManagerId -eq 'manager-1'
        }
    }

    It 'gives two people with the same name different UPNs in one batch' {
        $results = @(Get-TestHire; Get-TestHire) | New-M365Onboarding -Domain 'contoso.com' -AuditLogPath $script:Audit

        $results.UserPrincipalName | Should -Be @('jane.doe@contoso.com', 'jane.doe2@contoso.com')
    }

    It 'skips a UPN that already exists in the directory' {
        Mock Test-M365GraphUser -ModuleName M365Admin { $true } -ParameterFilter { $UserPrincipalName -eq 'jane.doe@contoso.com' }

        (Get-TestHire | New-M365Onboarding -Domain 'contoso.com' -AuditLogPath $script:Audit).UserPrincipalName |
            Should -Be 'jane.doe2@contoso.com'
    }

    It 'does not assign a licence when none are available' {
        $script:Available = 0

        $result = Get-TestHire | New-M365Onboarding -Domain 'contoso.com' -AuditLogPath $script:Audit

        $result.Status | Should -Be 'CompletedWithWarnings'
        $result.Message | Should -Match 'no available ENTERPRISEPACK'
        Should -Invoke Set-M365GraphUserLicense -ModuleName M365Admin -Times 0 -Exactly
    }

    It 'reports a missing group as a warning and still adds the others' {
        Mock Get-M365GraphGroupByName -ModuleName M365Admin { $null } -ParameterFilter { $DisplayName -eq 'Ghost Group' }

        $result = Get-TestHire -Groups 'Ghost Group;Sales' | New-M365Onboarding -Domain 'contoso.com' -AuditLogPath $script:Audit

        $result.Status | Should -Be 'CompletedWithWarnings'
        $result.GroupsAdded | Should -Be @('Sales')
        $result.Message | Should -Match 'Ghost Group'
    }

    It 'fails an invalid record without stopping the batch' {
        $batch = @(
            (Get-TestHire -Surname '')
            (Get-TestHire -GivenName 'John' -Surname 'Smith' -UsageLocation 'Canada')
            (Get-TestHire -GivenName 'Ana' -Surname 'Silva')
        )

        $results = $batch | New-M365Onboarding -Domain 'contoso.com' -AuditLogPath $script:Audit -WarningAction SilentlyContinue

        $results.Status | Should -Be @('Failed', 'Failed', 'Completed')
        $results[0].Message | Should -Match 'Surname'
        $results[1].Message | Should -Match 'two-letter'
        Should -Invoke New-M365GraphUser -ModuleName M365Admin -Times 1 -Exactly
    }

    It 'returns the temporary password only with -PassThruPassword' {
        (Get-TestHire | New-M365Onboarding -Domain 'contoso.com' -AuditLogPath $script:Audit).TemporaryPassword |
            Should -BeNullOrEmpty
        (Get-TestHire | New-M365Onboarding -Domain 'contoso.com' -AuditLogPath $script:Audit -PassThruPassword).TemporaryPassword |
            Should -Not -BeNullOrEmpty
    }

    It 'reads new hires from a CSV file' {
        $csv = Join-Path $TestDrive 'hires.csv'
        @((Get-TestHire), (Get-TestHire -GivenName 'Ana' -Surname 'Silva')) | Export-Csv -Path $csv -NoTypeInformation

        $results = New-M365Onboarding -CsvPath $csv -Domain 'contoso.com' -AuditLogPath $script:Audit

        $results.UserPrincipalName | Should -Be @('jane.doe@contoso.com', 'ana.silva@contoso.com')
    }

    It 'writes every action to the audit log' {
        Get-TestHire | New-M365Onboarding -Domain 'contoso.com' -AuditLogPath $script:Audit | Out-Null

        $log = Import-Csv $script:Audit
        $log.Action | Should -Be @('CreateUser', 'AssignLicense', 'AddGroup', 'SetManager')
        $log.Result | Sort-Object -Unique | Should -Be 'Success'
        $log[0].Target | Should -Be 'jane.doe@contoso.com'
        $log[0].TimestampUtc | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
    }
}
