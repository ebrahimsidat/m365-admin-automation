# m365-admin-automation

[![CI](https://github.com/ebrahimsidat/m365-admin-automation/actions/workflows/ci.yml/badge.svg)](https://github.com/ebrahimsidat/m365-admin-automation/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**M365Admin** is a PowerShell module that automates the Microsoft 365 and Entra ID (Azure AD) tasks service desks
repeat every week: onboarding new hires, securely offboarding leavers, and finding licences that can be reclaimed.
It uses the Microsoft Graph PowerShell SDK, supports `-WhatIf` on every change, writes an audit trail, and is tested
on PowerShell 7 (Windows and Linux) and Windows PowerShell 5.1.

## Commands

| Command | Purpose |
| --- | --- |
| `Connect-M365Admin` | Sign in to Microsoft Graph with the **least-privileged** scopes for the task, or app-only with a certificate |
| `New-M365Onboarding` | Bulk-create users from CSV: unique UPN, temporary password (change forced at first sign-in), licence, groups, manager |
| `Start-M365Offboarding` | Block sign-in, revoke sessions, optionally convert the mailbox to shared, remove groups, then remove licences |
| `Get-M365LicenseReport` | Licence utilisation per SKU, or licensed users who are disabled, never signed in, or inactive for N days |
| `New-M365UserPrincipalName` | Naming-convention UPNs with accent handling and collision checks |
| `New-M365TemporaryPassword` | Cryptographically secure passwords that meet Entra ID complexity rules |

## Quick start

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
Import-Module ./src/M365Admin/M365Admin.psd1

# Preview first: -WhatIf shows every change without touching the tenant
Connect-M365Admin -Task Onboarding
New-M365Onboarding -CsvPath ./examples/new-hires.csv -Domain contoso.com -WhatIf

# Then run it and keep the results (temporary passwords only with -PassThruPassword)
New-M365Onboarding -CsvPath ./examples/new-hires.csv -Domain contoso.com |
    Format-Table DisplayName, UserPrincipalName, Status, License, Message
```

```text
DisplayName      UserPrincipalName          Status                License        Message
-----------      -----------------          ------                -------        -------
Jane Doe         jane.doe@contoso.com       Completed             ENTERPRISEPACK
Mary Ann O'Brien maryann.obrien@contoso.com Completed             ENTERPRISEPACK
Luis Garcia      luis.garcia@contoso.com    CompletedWithWarnings                no available SPE_E3 licences
```

Offboarding a leaver (asks for confirmation unless `-Confirm:$false`):

```powershell
Connect-M365Admin -Task Offboarding
Connect-ExchangeOnline   # only needed for -ConvertToSharedMailbox
Start-M365Offboarding -UserPrincipalName jane.doe@contoso.com -ConvertToSharedMailbox
```

Licence reclamation:

```powershell
Connect-M365Admin -Task Reporting
Get-M365LicenseReport | Format-Table
Get-M365LicenseReport -IncludeInactiveUsers -InactiveDays 90 -Path ./reclaim.csv
```

## Design

- **Safe by default.** Every state-changing command supports `-WhatIf` and `-Confirm`; offboarding is
  `ConfirmImpact = 'High'`. Accounts are disabled, never deleted, so they can be restored or kept for legal hold.
- **Batch-resilient.** Each record is processed independently. A failure is reported in the result object and the audit
  log, and the rest of the batch continues.
- **Auditable.** Every action is appended to a CSV audit log (UTC timestamp, operator, action, target, result), including
  dry runs.
- **Least privilege.** Scopes are requested per task; reporting never requests write permissions. See
  [docs/permissions.md](docs/permissions.md).
- **Testable.** All Graph calls go through thin private wrappers, so the business logic is covered by Pester tests with
  no tenant access.

## Quality gates

| Check | Where |
| --- | --- |
| PSScriptAnalyzer (warnings and errors fail the build, with formatting rules) | CI and `./scripts/Invoke-Tests.ps1` |
| Pester 5 unit tests with code coverage | PowerShell 7 on Ubuntu and Windows, Windows PowerShell 5.1 |
| Module manifest, exports and comment-based help | Pester (`tests/Module.Tests.ps1`) |

## Documentation

- [Permissions and app registration](docs/permissions.md)
- [Operating procedures for onboarding and offboarding](docs/operating-procedures.md)

## License

[MIT](LICENSE) © 2026 Ebrahim Sidat
