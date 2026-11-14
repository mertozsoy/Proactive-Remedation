# Report Pending Reboot

Detection only script for Intune Remediations. Updates, app installs and renames wait for a restart that never comes. This script shows which devices are waiting and why.

## Files

| File | Purpose |
|---|---|
| `Detect-PendingReboot.ps1` | Checks CBS RebootPending, Windows Update RebootRequired, PendingFileRenameOperations, a pending computer rename, the ConfigMgr client state and uptime over `$MaxUptimeDays` (14). |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-PendingReboot.ps1` as the detection script. Leave the remediation script empty.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Detection only. The output lists the reason, which makes it easy to filter after export.
- For uptime only, see Report-DeviceUptime in this repo.
