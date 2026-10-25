#Requires -Version 5.1
<#
    M365Admin root module.
    Public functions are exported; Private functions (including the thin Microsoft Graph wrappers)
    stay internal so they can be mocked in tests and swapped without touching business logic.
#>
Set-StrictMode -Version Latest

$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to import $($file.FullName): $_"
    }
}

Export-ModuleMember -Function $public.BaseName
