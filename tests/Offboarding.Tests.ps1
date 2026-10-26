BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/M365Admin/M365Admin.psd1') -Force
    $script:E3 = [guid]'6fd2c87f-b296-42f0-b197-1e91e994b900'
}

Describe 'Start-M365Offboarding' {
    BeforeEach {
        $script:Audit = Join-Path $TestDrive "audit-$([guid]::NewGuid()).csv"

        Mock Get-M365GraphUser -ModuleName M365Admin {
            [pscustomobject]@{
                Id                = 'user-9'
                UserPrincipalName = 'leaver@contoso.com'
                AssignedLicenses  = @([pscustomobject]@{ SkuId = $script:E3 })
            }
        }
        Mock Disable-M365GraphUser -ModuleName M365Admin { }
        Mock Revoke-M365GraphUserSession -ModuleName M365Admin { }
        Mock Get-M365GraphUserGroup -ModuleName M365Admin {
            [pscustomobject]@{ Id = 'g-sales'; DisplayName = 'Sales'; Dynamic = $false }
            [pscustomobject]@{ Id = 'g-all'; DisplayName = 'All Staff'; Dynamic = $true }
        }
        Mock Remove-M365GraphGroupMember -ModuleName M365Admin { }
        Mock Set-M365GraphUserLicense -ModuleName M365Admin { }
        Mock Set-M365ExoMailboxType -ModuleName M365Admin { }
    }

    It 'makes no changes with -WhatIf' {
        $result = Start-M365Offboarding -UserPrincipalName 'leaver@contoso.com' -AuditLogPath $script:Audit -WhatIf

        $result.Status | Should -Be 'WhatIf'
        Should -Invoke Disable-M365GraphUser -ModuleName M365Admin -Times 0 -Exactly
        Should -Invoke Set-M365GraphUserLicense -ModuleName M365Admin -Times 0 -Exactly
    }

    It 'blocks sign-in, revokes sessions, removes assigned groups and licences' {
        $result = Start-M365Offboarding -UserPrincipalName 'leaver@contoso.com' -AuditLogPath $script:Audit -Confirm:$false

        $result.Status | Should -Be 'Completed'
        @($result.Steps.Keys) | Should -Be @('BlockSignIn', 'RevokeSessions', 'RemoveGroups', 'RemoveLicenses')
        $result.GroupsRemoved | Should -Be @('Sales')
        Should -Invoke Disable-M365GraphUser -ModuleName M365Admin -Times 1 -Exactly -ParameterFilter { $UserId -eq 'user-9' }
        Should -Invoke Revoke-M365GraphUserSession -ModuleName M365Admin -Times 1 -Exactly
        Should -Invoke Remove-M365GraphGroupMember -ModuleName M365Admin -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'g-sales' }
        Should -Invoke Set-M365GraphUserLicense -ModuleName M365Admin -Times 1 -Exactly -ParameterFilter {
            $RemoveSkuId -contains $script:E3 -and @($AddSkuId).Count -eq 0
        }
    }

    It 'never removes members from dynamic groups' {
        Start-M365Offboarding -UserPrincipalName 'leaver@contoso.com' -AuditLogPath $script:Audit -Confirm:$false | Out-Null

        Should -Invoke Remove-M365GraphGroupMember -ModuleName M365Admin -Times 0 -Exactly -ParameterFilter { $GroupId -eq 'g-all' }
    }

    It 'converts the mailbox before licences are removed when asked' {
        $result = Start-M365Offboarding -UserPrincipalName 'leaver@contoso.com' -ConvertToSharedMailbox -AuditLogPath $script:Audit -Confirm:$false

        @($result.Steps.Keys) | Should -Be @('BlockSignIn', 'RevokeSessions', 'ConvertToSharedMailbox', 'RemoveGroups', 'RemoveLicenses')
        Should -Invoke Set-M365ExoMailboxType -ModuleName M365Admin -Times 1 -Exactly -ParameterFilter { $Identity -eq 'leaver@contoso.com' }
    }

    It 'keeps licences with -KeepLicenses' {
        $result = Start-M365Offboarding -UserPrincipalName 'leaver@contoso.com' -KeepLicenses -AuditLogPath $script:Audit -Confirm:$false

        $result.Steps['RemoveLicenses'] | Should -Be 'Skipped'
        Should -Invoke Set-M365GraphUserLicense -ModuleName M365Admin -Times 0 -Exactly
    }

    It 'continues after a failed step and reports it' {
        Mock Revoke-M365GraphUserSession -ModuleName M365Admin { throw 'Service unavailable' }

        $result = Start-M365Offboarding -UserPrincipalName 'leaver@contoso.com' -AuditLogPath $script:Audit -Confirm:$false

        $result.Status | Should -Be 'CompletedWithWarnings'
        $result.Steps['RevokeSessions'] | Should -Match 'Service unavailable'
        $result.Message | Should -Match 'RevokeSessions'
        Should -Invoke Set-M365GraphUserLicense -ModuleName M365Admin -Times 1 -Exactly
    }

    It 'reports Failed when sign-in cannot be blocked' {
        Mock Disable-M365GraphUser -ModuleName M365Admin { throw 'Insufficient privileges' }

        (Start-M365Offboarding -UserPrincipalName 'leaver@contoso.com' -AuditLogPath $script:Audit -Confirm:$false).Status |
            Should -Be 'Failed'
    }

    It 'fails cleanly for an unknown user' {
        Mock Get-M365GraphUser -ModuleName M365Admin { $null }

        $result = Start-M365Offboarding -UserPrincipalName 'ghost@contoso.com' -AuditLogPath $script:Audit -Confirm:$false -WarningAction SilentlyContinue

        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Match 'not found'
        Should -Invoke Disable-M365GraphUser -ModuleName M365Admin -Times 0 -Exactly
    }

    It 'accepts several users from the pipeline' {
        $results = 'a@contoso.com', 'b@contoso.com' | Start-M365Offboarding -AuditLogPath $script:Audit -Confirm:$false

        @($results).Count | Should -Be 2
        Should -Invoke Disable-M365GraphUser -ModuleName M365Admin -Times 2 -Exactly
    }

    It 'rejects a malformed user principal name' {
        { Start-M365Offboarding -UserPrincipalName 'not-an-upn' -Confirm:$false } | Should -Throw
    }

    It 'audits each step' {
        Start-M365Offboarding -UserPrincipalName 'leaver@contoso.com' -AuditLogPath $script:Audit -Confirm:$false | Out-Null

        (Import-Csv $script:Audit).Action | Should -Be @('BlockSignIn', 'RevokeSessions', 'RemoveGroups', 'RemoveLicenses')
    }
}
