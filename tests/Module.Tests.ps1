BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '../src/M365Admin'
    $script:ManifestPath = Join-Path $script:ModuleRoot 'M365Admin.psd1'
    Import-Module $script:ManifestPath -Force
}

AfterAll {
    Remove-Module M365Admin -ErrorAction SilentlyContinue
}

Describe 'Module manifest' {
    It 'is valid' {
        { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports exactly the functions in the Public folder' {
        $expected = @(Get-ChildItem (Join-Path $script:ModuleRoot 'Public') -Filter '*.ps1').BaseName | Sort-Object
        $exported = @((Get-Module M365Admin).ExportedFunctions.Keys) | Sort-Object
        $exported | Should -Be $expected
    }

    It 'does not export private Graph wrappers' {
        Get-Command -Module M365Admin -Name 'New-M365GraphUser' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}

Describe 'Comment-based help for <_>' -ForEach @(
    'Connect-M365Admin', 'New-M365UserPrincipalName', 'New-M365TemporaryPassword',
    'New-M365Onboarding', 'Start-M365Offboarding', 'Get-M365LicenseReport'
) {
    BeforeAll {
        $script:Help = Get-Help -Name $_ -Full
    }

    It 'has a synopsis' {
        $script:Help.Synopsis | Should -Not -BeNullOrEmpty
        $script:Help.Synopsis | Should -Not -Match "^\s*$_\s*$"
    }

    It 'has a description' {
        ($script:Help.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty
    }

    It 'has at least one example' {
        @($script:Help.Examples.Example).Count | Should -BeGreaterThan 0
    }
}
