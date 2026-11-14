# Remove Orphaned User Folders

Intune Remediations script pair. When a profile is removed but the folder stays under the profiles root, Windows creates a new folder with a `.000` suffix on the next sign-in. This pair finds folders that have no ProfileList entry and removes them.

## Files

| File | Purpose |
|---|---|
| `Detect-OrphanedUserFolders.ps1` | Reads `ProfilesDirectory` and every `ProfileImagePath` from ProfileList, then lists folders under the profiles root that have no matching entry, are not loaded and are older than `$MinAgeDays`. |
| `Remediate-OrphanedUserFolders.ps1` | Deletes those folders with `Remove-Item`, retries once on a locked folder and verifies the path is gone. `$RemoveFolders = $false` switches the script to a report only pass. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-OrphanedUserFolders.ps1` as the detection script and `Remediate-OrphanedUserFolders.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Keep `$MinAgeDays` and `$ExcludeNames` the same in both scripts.
- `$RemoveFolders = $false` by default: the pair only reports. Every folder the script deletes is user data and there is no backup. Read the list from a pilot group before you enable deletion.
- Folders younger than `$MinAgeDays` (7 days) are skipped so a profile that is being created is never touched.
- Junctions, `Public`, `Default`, `Default User` and `defaultuser0` are excluded.
- Locked folders are left in place and reported with `Failed`. Nothing is forced and no reboot is requested.
