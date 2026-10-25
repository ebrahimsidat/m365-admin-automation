# Operating procedures

## Onboarding

1. HR provides the new-hire file using the columns in [`examples/new-hires.csv`](../examples/new-hires.csv).
   `GivenName`, `Surname` and `UsageLocation` are required; `Groups` is a `;`-separated list of group display names.
2. Run a dry run and review the proposed user principal names:

   ```powershell
   New-M365Onboarding -CsvPath .\new-hires.csv -Domain contoso.com -WhatIf
   ```

3. Run the onboarding and save the results:

   ```powershell
   New-M365Onboarding -CsvPath .\new-hires.csv -Domain contoso.com -PassThruPassword |
       Export-Csv .\onboarded.csv -NoTypeInformation
   ```

4. Deliver each temporary password to the hiring manager through an approved secure channel, then delete
   `onboarded.csv`. Users must change the password at first sign-in.
5. Resolve any `CompletedWithWarnings` rows (for example, buy licences or create a missing group) and attach the audit
   log to the ticket.

## Offboarding

Run on the employee's last day, or immediately for an involuntary departure.

1. Confirm the request in the ticketing system (HR approval, last working day, mailbox delegate if any).
2. Preview:

   ```powershell
   Start-M365Offboarding -UserPrincipalName jane.doe@contoso.com -ConvertToSharedMailbox -WhatIf
   ```

3. Run it. Steps are performed in this order so access is cut first and data is preserved:

   | Step | Effect |
   | --- | --- |
   | BlockSignIn | No new sign-ins |
   | RevokeSessions | Existing sessions and refresh tokens are invalidated |
   | ConvertToSharedMailbox (optional) | Mailbox remains accessible to delegates without a licence |
   | RemoveGroups | Assigned group memberships removed (dynamic groups are skipped) |
   | RemoveLicenses | Licences returned to the pool |

4. If the result is `CompletedWithWarnings`, re-run the failed step after fixing the cause. A `Failed` result means
   sign-in could not be blocked: escalate immediately.
5. Attach the audit log to the ticket. Delete the account only after the retention period in your policy.

## Monthly licence review

```powershell
Get-M365LicenseReport | Export-Csv .\licence-summary.csv -NoTypeInformation
Get-M365LicenseReport -IncludeInactiveUsers -InactiveDays 90 -Path .\licence-reclaim.csv
```

Confirm each reclamation candidate with the user's manager before removing licences.
