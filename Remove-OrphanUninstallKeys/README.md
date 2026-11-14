# Remove Orphan Uninstall Keys

Removed or manually deleted applications can leave their uninstall registry key behind. Intune discovered apps and Defender TVM then list versions that are no longer installed. This pair finds those ghost entries, backs them up and deletes them.

## Files

| File | Purpose |
|---|---|
| `Detect-OrphanUninstallKeys.ps1` | Scans the 64-bit, 32-bit and optional user uninstall keys. Flags entries whose uninstall executable and install folder are both missing. |
| `Remediate-OrphanUninstallKeys.ps1` | Exports each ghost key with reg export, deletes the key and rescans the device. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-OrphanUninstallKeys.ps1` as the detection script and `Remediate-OrphanUninstallKeys.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Weekly, or one time with a cleanup assignment.
5. Assign to a pilot group first and check the output before widening the scope.

## Notes

- MSI entries, updates, patches and SystemComponent entries are skipped. Only entries with a missing uninstaller file and a missing install folder are removed.
- Backups are written to %ProgramData%\IntuneRemediations\Backup\OrphanUninstallKeys. A failed export stops the delete for that entry.
- User hives under HKEY_USERS are not scanned unless `$IncludeUserHives` is set to `$true` in both scripts.
- Set `$EnableRemediation` to `$false` to report without deleting.
- The script removes the registry entry only. Application files stay on disk.
