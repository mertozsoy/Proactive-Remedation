# Remove Stale Credential Entries

Intune Remediations script pair. A file server, an RDP host or an Azure Files share is retired, but the saved credentials in the user's Credential Manager stay behind. Windows keeps offering the old password and accounts get locked. This pair matches the stored targets against a retired target list and deletes the matches.

## Files

| File | Purpose |
|---|---|
| `Detect-StaleCredentialEntries.ps1` | Runs as the user. Lists the stored credentials with `CredEnumerate`, keeps the persisted ones that belong to `$TargetTypes`, and matches `TargetName` against `$RetiredTargets`. `$KeepTargets` protects names you want to keep. Exits 1 when a retired target still has a credential. |
| `Remediate-StaleCredentialEntries.ps1` | Repeats the scan, writes the matched target names to a record file, and deletes each entry with `CredDelete`. Checks the store again afterwards. `$RemoveCredentials` is `$false` by default, so the first run only reports. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-StaleCredentialEntries.ps1` as the detection script and `Remediate-StaleCredentialEntries.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily, or weekly if your retired target list changes rarely.
5. Assign to a pilot group first, check the detection output, then widen the scope.

## Notes

- Add your retired targets to `$RetiredTargets` in both scripts. Values with `*` or `?` are matched with `-like`. `legacyfs01.contoso.local` is an example.
- `$RemoveCredentials` is `$false` by default. Set it to `$true` after the pilot output looks correct, otherwise the remediation keeps reporting the same entries.
- Only the credential set of the signed-in user is read. Session-only entries are skipped.
- Stored secrets are never read or written. The record file under `%LOCALAPPDATA%\IntuneRemediations\Records` holds target names only.
- Assign to user groups. A device group does not cover users who have not signed in yet.
