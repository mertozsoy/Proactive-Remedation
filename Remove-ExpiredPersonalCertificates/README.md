# Remove Expired Personal Certificates

Expired personal-store certificates can clutter certificate selection. These scripts inspect CurrentUser My and LocalMachine My and remove approved expired entries after a verified public-certificate backup. Removal is disabled until explicitly enabled.

## Files

| File | Purpose |
|---|---|
| `Detect-ExpiredPersonalCertificates.ps1` | Counts expired certificates in the selected personal stores, excluding retained entries. |
| `Remediate-ExpiredPersonalCertificates.ps1` | Backs up and removes approved expired certificates, retains private keys and verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations > Create**. Upload both scripts.
2. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**, unless signed for your environment.
3. Keep `$StoreLocations` and `$ExcludedThumbprints` identical in both scripts. Use 40-character hexadecimal thumbprints without spaces.
4. Review each removal target locally. Add only retired certificates with no active policy, enrollment, application binding or historical decryption dependency to the appropriate approval list. Set `$RemoveExpiredCertificates = $true` after approval.
5. Assign to a pilot group and schedule daily. For machine cleanup, create a separate System deployment with logged-on credentials **No**, `$StoreLocations = @('LocalMachine')` in both scripts and `Run As: System` in both help blocks.

## Notes

- Default USER execution inspects both stores; machine removal requires an elevated token and otherwise reports `RequiresElevation`. No elevation is attempted.
- Expiry alone does not prove a certificate is disposable. Retain EFS, S/MIME, enrollment and actively managed certificates; exclusions override approvals.
- Unapproved or blocked expired entries keep exit 1; exit 0 means no non-excluded expired entries remain. No renewal or replacement is performed.
- CER backups exclude private keys; keys are retained but recovery is not guaranteed. Backups use `%LOCALAPPDATA%\IntuneRemediations\Backup\ExpiredPersonalCertificates` for User or `%ProgramData%\IntuneRemediations\Backup\ExpiredPersonalCertificates` for System.
- Only selected My stores are changed. System mode rejects CurrentUser scope; other user profiles, trust stores and policy assignments are untouched.
