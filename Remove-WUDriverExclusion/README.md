# Remove Windows Update Driver Exclusion

A retired driver exclusion can block approved driver updates. These scripts detect ExcludeWUDriversInQualityUpdate set to DWORD 1 and remove that value after policy review and backup.

## Files

| File | Purpose |
|---|---|
| Detect-WUDriverExclusion.ps1 | Detects the machine driver exclusion without changing it. |
| Remediate-WUDriverExclusion.ps1 | Backs up the parent key, removes the approved exclusion and verifies absence. |

## Deployment (Intune)

1. Confirm the target devices use Intune driver update policies or Autopatch driver management. Set DriverRingsConfirmed to true in both scripts.
2. Review domain and local GPO, Intune update rings, Settings Catalog and other management tools. Retire the exclusion at its source and allow policy synchronization. Only then set PolicySourcesRetired to true in both scripts.
3. Go to **Devices > Manage devices > Scripts and remediations > Remediations > Create** and select both scripts.
4. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**, unless signed under your signing policy.
5. Assign to a pilot device group. Schedule daily for a short cleanup period and remove the assignment after verification.

## Notes

- Both confirmations default to false; deletion is blocked until review is complete. Policy ownership is confirmed by the administrator, not discovered automatically.
- Only HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\ExcludeWUDriversInQualityUpdate DWORD 1 is removed; zero is left unchanged.
- Backups are in %ProgramData%\IntuneRemediations\Backup\WUDriverExclusion. Review the export before restoring because it contains the parent key.
- PolicyManager and CSP state are not edited. If the value returns, stop cleanup and correct the active source policy.
- Successful removal does not confirm driver installation or clear every Autopatch warning; approvals, scan sources and reporting still need review.
