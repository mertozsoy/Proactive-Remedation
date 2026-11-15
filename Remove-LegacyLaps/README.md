# Remove Legacy LAPS

Legacy Microsoft LAPS software and policy remnants can remain after a Windows LAPS migration. These scripts detect the remnants and remove them after migration approval and native password backup checks.

## Files

| File | Purpose |
|---|---|
| `Detect-LegacyLaps.ps1` | Checks Microsoft legacy LAPS uninstall entries, AdmPwd CSE registration and legacy policy. |
| `Remediate-LegacyLaps.ps1` | Uninstalls legacy MSI software and removes approved remnants with registry backups and final verification. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-LegacyLaps.ps1` and `Remediate-LegacyLaps.ps1`.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Retire legacy GPO, Intune and software deployment assignments. Confirm the current account password is recoverable from the intended directory, then set `$LegacyPolicyRetiredConfirmed = $true`.
5. Configure the removal switches below. Assign to a pilot group and schedule daily during migration.

## Notes

- Removal is blocked by default. Set `$RemoveStalePolicy = $true` only for confirmed unmanaged remnants; active policies must be removed at their source.
- `$ExpectedBackupDirectory` is 1 for Entra ID or 2 for AD. A native backup and local password update in one successful cycle within 45 days are required; this is historical evidence, not a current recovery test.
- Manual CSE cleanup requires `$RemoveManualCse = $true` and its exact absolute AdmPwd.dll path in `$ApprovedManualDllPaths`. Only a valid Microsoft-signed DLL is executed; unsupported registrations remain blocked.
- Registry backups and manual DLL backups go under `%ProgramData%\IntuneRemediations\Backup\LegacyLaps`. MSI removal also removes any legacy management tools installed by that product.
- No passwords, accounts, AD attributes or native LAPS policies are changed. Exit 3010 reports a pending restart without initiating one; `Fixed` confirms remnant removal, not a new password backup.
