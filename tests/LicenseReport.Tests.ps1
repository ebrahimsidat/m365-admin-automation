BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/M365Admin/M365Admin.psd1') -Force
}

Describe 'Get-M365LicenseReport' {
    BeforeAll {
        Mock Get-M365GraphSubscribedSku -ModuleName M365Admin {
            [pscustomobject]@{
                SkuId         = [guid]'6fd2c87f-b296-42f0-b197-1e91e994b900'
                SkuPartNumber = 'ENTERPRISEPACK'
                ConsumedUnits = 90
                PrepaidUnits  = [pscustomobject]@{ Enabled = 100; Suspended = 0; Warning = 0 }
            }
            [pscustomobject]@{
                SkuId         = [guid]'f30db892-07e9-47e9-837c-80727f46fd3d'
                SkuPartNumber = 'FLOW_FREE'
                ConsumedUnits = 3
                PrepaidUnits  = [pscustomobject]@{ Enabled = 10000; Suspended = 0; Warning = 0 }
            }
            [pscustomobject]@{
                SkuId         = [guid]'05e9a617-0261-4cee-bb44-138d3ef5d965'
                SkuPartNumber = 'SPE_E3'
                ConsumedUnits = 0
                PrepaidUnits  = [pscustomobject]@{ Enabled = 0; Suspended = 5; Warning = 0 }
            }
        }

        Mock Get-M365GraphLicensedUser -ModuleName M365Admin {
            $e3 = [pscustomobject]@{ SkuId = [guid]'6fd2c87f-b296-42f0-b197-1e91e994b900' }
            $unknown = [pscustomobject]@{ SkuId = [guid]'00000000-0000-0000-0000-000000000001' }
            [pscustomobject]@{ UserPrincipalName = 'active@contoso.com'; DisplayName = 'Active'; AccountEnabled = $true; AssignedLicenses = @($e3); SignInActivity = [pscustomobject]@{ LastSignInDateTime = [DateTime]::UtcNow.AddDays(-3) } }
            [pscustomobject]@{ UserPrincipalName = 'stale@contoso.com'; DisplayName = 'Stale'; AccountEnabled = $true; AssignedLicenses = @($e3, $unknown); SignInActivity = [pscustomobject]@{ LastSignInDateTime = [DateTime]::UtcNow.AddDays(-120) } }
            [pscustomobject]@{ UserPrincipalName = 'never@contoso.com'; DisplayName = 'Never'; AccountEnabled = $true; AssignedLicenses = @($e3); SignInActivity = $null }
            [pscustomobject]@{ UserPrincipalName = 'left@contoso.com'; DisplayName = 'Left'; AccountEnabled = $false; AssignedLicenses = @($e3); SignInActivity = [pscustomobject]@{ LastSignInDateTime = [DateTime]::UtcNow.AddDays(-1) } }
        }
    }

    Context 'summary' {
        BeforeAll {
            $script:Report = Get-M365LicenseReport
        }

        It 'returns one row per SKU, highest utilisation first' {
            $script:Report.Sku | Should -Be @('ENTERPRISEPACK', 'FLOW_FREE', 'SPE_E3')
        }

        It 'calculates assigned, available and utilisation' {
            $e3 = $script:Report | Where-Object Sku -EQ 'ENTERPRISEPACK'
            $e3.Purchased | Should -Be 100
            $e3.Assigned | Should -Be 90
            $e3.Available | Should -Be 10
            $e3.UtilizationPct | Should -Be 90
        }

        It 'handles SKUs with no purchased units' {
            ($script:Report | Where-Object Sku -EQ 'SPE_E3').UtilizationPct | Should -Be 0
            ($script:Report | Where-Object Sku -EQ 'SPE_E3').Suspended | Should -Be 5
        }
    }

    Context 'inactive users' {
        BeforeAll {
            $script:Inactive = Get-M365LicenseReport -IncludeInactiveUsers -InactiveDays 90
        }

        It 'excludes recently active users' {
            $script:Inactive.UserPrincipalName | Should -Not -Contain 'active@contoso.com'
        }

        It 'flags disabled, never-signed-in and inactive users' {
            ($script:Inactive | Where-Object UserPrincipalName -EQ 'left@contoso.com').Reason | Should -Be 'AccountDisabled'
            ($script:Inactive | Where-Object UserPrincipalName -EQ 'never@contoso.com').Reason | Should -Be 'NeverSignedIn'
            ($script:Inactive | Where-Object UserPrincipalName -EQ 'stale@contoso.com').Reason | Should -Be 'Inactive'
        }

        It 'resolves SKU names and keeps unknown SKU ids' {
            ($script:Inactive | Where-Object UserPrincipalName -EQ 'stale@contoso.com').Licenses |
                Should -Be 'ENTERPRISEPACK;00000000-0000-0000-0000-000000000001'
        }

        It 'reports days since last sign-in' {
            ($script:Inactive | Where-Object UserPrincipalName -EQ 'stale@contoso.com').DaysSinceSignIn | Should -BeIn 119, 120
        }

        It 'respects -InactiveDays' {
            (Get-M365LicenseReport -IncludeInactiveUsers -InactiveDays 365).UserPrincipalName |
                Should -Not -Contain 'stale@contoso.com'
        }
    }

    It 'writes a CSV when -Path is given' {
        $path = Join-Path $TestDrive 'licences.csv'
        Get-M365LicenseReport -Path $path | Out-Null
        (Import-Csv $path).Count | Should -Be 3
    }
}
