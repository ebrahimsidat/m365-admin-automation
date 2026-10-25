@{
    RootModule           = 'M365Admin.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = '6f1c9a52-3d7e-4b8a-9c21-5e4f0a7b2d63'
    Author               = 'Ebrahim Sidat'
    CompanyName          = 'Ebrahim Sidat'
    Copyright            = '(c) 2026 Ebrahim Sidat. MIT License.'
    Description          = 'Microsoft 365 and Entra ID administration: bulk onboarding, secure offboarding and licence utilisation reporting through Microsoft Graph, with -WhatIf support and audit logging.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @(
        'Connect-M365Admin'
        'New-M365UserPrincipalName'
        'New-M365TemporaryPassword'
        'New-M365Onboarding'
        'Start-M365Offboarding'
        'Get-M365LicenseReport'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('Microsoft365', 'EntraID', 'AzureAD', 'MicrosoftGraph', 'Onboarding', 'Offboarding', 'Licensing')
            LicenseUri   = 'https://github.com/ebrahimsidat/m365-admin-automation/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/ebrahimsidat/m365-admin-automation'
            ReleaseNotes = 'Initial release.'
        }
    }
}
