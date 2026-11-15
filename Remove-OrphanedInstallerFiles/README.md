# Remove Orphaned Installer Files

C:\Windows\Installer caches the MSI and MSP files that Windows Installer needs for repair and uninstall. Adobe Acrobat updates arrive as MSP patches, so the folder can grow to 50 GB or more. Most of those files are no longer referenced by any product. This script pair finds MSI and MSP files that no registered product or patch references and removes them.

## Files

| File | Purpose |
|---|---|
| `Detect-OrphanedInstallerFiles.ps1` | Reads the cached package path of every registered product and patch and lists MSI and MSP files in the cache that no product references and that are older than `$MinimumAgeDays`. |
| `Remediate-OrphanedInstallerFiles.ps1` | Rebuilds the same reference list, deletes the orphan files and rescans the folder to confirm the result. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Upload `Detect-OrphanedInstallerFiles.ps1` and `Remediate-OrphanedInstallerFiles.ps1` in their fields.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** unless both scripts are signed.
4. Schedule: Weekly. Start with a pilot group and check the reported orphan size before you widen the assignment.
5. Keep `$MinimumAgeDays` and `$MinimumOrphanMB` identical in both scripts.

## Notes

- Referenced packages are never deleted. The list covers per-machine and per-user managed installs.
- `$MinimumAgeDays = 7` keeps recent files untouched because an install that started minutes ago may not be registered yet.
- `$EnableRemediation = $false` by default: the pair only reports. Deletion is permanent with no backup, and a wrongly removed package breaks repair and uninstall of that app. Review the list on a pilot group first.
- `$MaxFilesPerRun = 200` limits each run to the largest files. The rest goes on the next run.
- A locked file is counted as Failed. The log names it and the next run tries again.
