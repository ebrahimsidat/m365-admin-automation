# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-10-25

### Added

- M365Admin module: New-M365Onboarding, Start-M365Offboarding, Get-M365LicenseReport, Connect-M365Admin
- Naming-convention UPN generation with accent handling and collision checks
- Cryptographically secure temporary passwords
- -WhatIf support and CSV audit log for every change
- Least-privilege Graph scopes and certificate-based app-only sign-in
- CI: PSScriptAnalyzer and Pester on PowerShell 7 (Ubuntu, Windows) and Windows PowerShell 5.1
