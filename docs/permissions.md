# Permissions and app registration

## Delegated (interactive) use

`Connect-M365Admin -Task <task>` requests only what that task needs:

| Task | Microsoft Graph scopes | Minimum Entra ID role |
| --- | --- | --- |
| Onboarding | `User.ReadWrite.All`, `Group.ReadWrite.All`, `Organization.Read.All` | User Administrator + License Administrator |
| Offboarding | `User.ReadWrite.All`, `Group.ReadWrite.All`, `User.RevokeSessions.All` | User Administrator (Exchange Administrator for mailbox conversion) |
| Reporting | `User.Read.All`, `Organization.Read.All`, `AuditLog.Read.All` | Global Reader or Reports Reader |

Delegated permissions are limited by the signed-in administrator's role, so use the least-privileged role above rather
than Global Administrator. Activate roles just in time with Privileged Identity Management where available.

## Unattended (app-only) use

For scheduled jobs such as `examples/Invoke-WeeklyLicenseReport.ps1`:

1. Register an application in Entra ID (single tenant).
2. Add **application** permissions only for the job, for example `Organization.Read.All`, `User.Read.All` and
   `AuditLog.Read.All` for reporting, and grant admin consent.
3. Upload a certificate (no client secrets). Keep the private key in the machine certificate store or Azure Key Vault.
4. Connect with:

   ```powershell
   Connect-M365Admin -ClientId <app-id> -TenantId contoso.onmicrosoft.com -CertificateThumbprint <thumbprint>
   ```

5. Review the app's sign-in logs and permissions quarterly.

## Notes

- Last sign-in data (`signInActivity`) requires `AuditLog.Read.All` and an Entra ID P1 or P2 licence.
- Licence assignment requires each user to have a `UsageLocation`; onboarding enforces a two-letter country code.
- The audit log contains user principal names. Store it according to your records-retention policy.
