# Remove Duplicate OneDrive Entry

Intune Remediations script pair. Some users see two identical OneDrive entries in the File Explorer navigation pane after a reinstall, an account change or a tenant move. One entry points to a folder that no longer exists. This pair finds the duplicate registration and removes it.

## Files

| File | Purpose |
|---|---|
| `Detect-DuplicateOneDriveEntry.ps1` | Reads the File Explorer desktop namespace of the user and the machine, resolves the display name, the target folder and the pin state of every OneDrive entry, and exits 1 when a name is registered twice. |
| `Remediate-DuplicateOneDriveEntry.ps1` | Exports the namespace key, keeps the entry that points to an existing folder and deletes the other per-user registrations. Verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-DuplicateOneDriveEntry.ps1` as the detection script and `Remediate-DuplicateOneDriveEntry.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- The namespace key is exported to `%ProgramData%\IntuneRemediations\Backup` before any deletion, or to `%LOCALAPPDATA%` when ProgramData is not writable.
- Only per-user entries are removed. A duplicate registered under `HKLM` needs an administrator and is reported as `Blocked`.
- The entry that points to an existing folder is kept. Machine registration and pin state break a tie. The last remaining OneDrive entry is never removed.
- No files, sync data or OneDrive settings are touched. Files stay where they are; only the navigation pane registration is removed.
- OneDrive rebuilds the entry on the next start. An open Explorer window keeps the old tree until it is closed or the user signs out.
