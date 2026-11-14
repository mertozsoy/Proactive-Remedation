# Remove Aged Recycle Bin Items

Storage Sense may leave old Recycle Bin items behind. This script pair finds items deleted more than 30 days ago and can permanently remove their content and metadata. It runs as SYSTEM without changing Storage Sense settings.

## Files

| File | Purpose |
|---|---|
| `Detect-AgedRecycleBinItems.ps1` | Reads deletion timestamps from Recycle Bin metadata and flags aged items or inspection issues. |
| `Remediate-AgedRecycleBinItems.ps1` | Revalidates aged pairs, removes their content before metadata and verifies the remaining inventory. Deletion is disabled by default. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Upload the detection and remediation scripts from the Files table.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**, unless you sign both scripts.
4. Keep `RetentionDays` and `DriveLetters` identical in both scripts. Confirm that the selected devices require fallback cleanup and their effective retention policy permits it.
5. Assign to a pilot group with a daily schedule. Review detection results before setting `RemoveFiles` to `$true` in the remediation script.

## Notes

- `RemoveFiles = $false` reports without deleting. Enabled cleanup is permanent and has no backup or undo.
- Default scope is C: and all SID folders in its Recycle Bin. Add other fixed NTFS drive letters explicitly; network, removable and folder-mounted volumes are excluded.
- Age comes from the embedded UTC deletion timestamp in validated version 1 or 2 metadata, not file modification time. Unknown or malformed records remain untouched.
- Inspection issues block cleanup. Reparse points, inaccessible content and orphan pairs require review; partial deletion is possible if an operation fails.
- Old items do not prove Storage Sense stopped. Confirm effective policy before enabling cleanup; the scripts neither diagnose its runtime nor override retention settings.
