<#
.SYNOPSIS
    Runs PSScriptAnalyzer and the Pester suite exactly as CI does.
.EXAMPLE
    ./scripts/Invoke-Tests.ps1
.EXAMPLE
    ./scripts/Invoke-Tests.ps1 -CodeCoverage
#>
[CmdletBinding()]
param(
    [switch]$CodeCoverage
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent

foreach ($module in @(@{ Name = 'Pester'; Version = '5.6.0' }, @{ Name = 'PSScriptAnalyzer'; Version = '1.22.0' })) {
    if (-not (Get-Module -ListAvailable -Name $module.Name | Where-Object Version -GE $module.Version)) {
        throw "$($module.Name) $($module.Version) or later is required: Install-Module $($module.Name) -Scope CurrentUser -SkipPublisherCheck"
    }
}

Write-Information 'Running PSScriptAnalyzer...' -InformationAction Continue
$findings = Invoke-ScriptAnalyzer -Path (Join-Path $root 'src') -Recurse -Settings (Join-Path $root 'PSScriptAnalyzerSettings.psd1')
if ($findings) {
    $findings | Format-Table -AutoSize RuleName, Severity, ScriptName, Line, Message
    throw "PSScriptAnalyzer reported $(@($findings).Count) finding(s)."
}
Write-Information 'PSScriptAnalyzer: no findings.' -InformationAction Continue

Import-Module Pester -MinimumVersion 5.6.0
$config = New-PesterConfiguration
$config.Run.Path = Join-Path $root 'tests'
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $root 'testResults.xml'
if ($CodeCoverage) {
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = Join-Path $root 'src/M365Admin/Public'
    $config.CodeCoverage.OutputPath = Join-Path $root 'coverage.xml'
}
Invoke-Pester -Configuration $config
