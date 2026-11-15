# Remove Known Bad File

A bad signed file or driver can take down a whole fleet in minutes. Waiting for a vendor fix or a manual cleanup per device is not an option. This script pair finds files that match a configured folder, name pattern and optional SHA256 hash, and deletes them on every assigned device.

## Files

| File | Purpose |
|---|---|
| `Detect-KnownBadFile.ps1` | Scans the folders in `$Targets` for files that match the name pattern and the optional hash. Exits 1 when a match exists. |
| `Remediate-KnownBadFile.ps1` | Rebuilds the same list, copies each match to a backup folder, stops the configured services and deletes the files. The delete step is off by default. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Upload `Detect-KnownBadFile.ps1` as the detection script and `Remediate-KnownBadFile.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Edit `$Targets` in both scripts so the folder, name pattern and hash match the file you are chasing. Keep the block identical in both files.
5. Assign to a pilot group first. Run once on demand during an incident. Remove the assignment after the vendor fix is deployed.
6. Set `$EnableRemediation = $true` in the remediation script only when you are ready to delete. The default is report mode.

## Notes

- `$Targets` is empty by default and the pair returns NotApplicable. A target with an empty `Pattern` and an empty `Hash` is skipped, which prevents a folder-wide delete by accident.
- Files are copied to `%ProgramData%\IntuneRemediations\Backup\KnownBadFile\<timestamp>` before the delete.
- A file that is still locked is counted as Failed. The script does not force a reboot and does not touch PendingFileRenameOperations.
- `$ServiceNames` only stops services. The script does not change their start type and does not restart them.
- Keep the detection and remediation `$Targets` list identical, otherwise the two scripts disagree on what is bad.
