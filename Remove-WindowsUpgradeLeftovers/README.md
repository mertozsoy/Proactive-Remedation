# Remove Windows Upgrade Leftovers

After a feature update Windows keeps Windows.old, $WINDOWS.~BT and $WINDOWS.~WS on the system drive. These folders hold the previous installation and setup files, often 20 GB or more. This script pair removes leftovers that are past the rollback window and cleans the component store.

## Files

| File | Purpose |
|---|---|
| `Detect-WindowsUpgradeLeftovers.ps1` | Reports Windows.old, $WINDOWS.~BT and $WINDOWS.~WS when their last change is older than `$MinimumAgeDays`. |
| `Remediate-WindowsUpgradeLeftovers.ps1` | Rechecks each folder, removes it and runs DISM StartComponentCleanup. Takes ownership only when a direct delete is denied. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Upload `Detect-WindowsUpgradeLeftovers.ps1` and `Remediate-WindowsUpgradeLeftovers.ps1` in their fields.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** unless both scripts are signed.
4. Schedule: Weekly. Start with a pilot group and check the detected size before you enable the assignment for all devices.
5. Keep the age and folder settings identical in both scripts.

## Notes

- Default `$MinimumAgeDays = 10` matches the Windows rollback window. After that window the previous version cannot be restored anyway.
- Removal is permanent and there is no backup. Set `$RemoveLeftovers = $false` to only report.
- `$ResetBase` is off by default. When enabled it removes all superseded components and installed updates can no longer be uninstalled.
- A running setup process blocks the script. DISM can take a long time and may return 3010; the script never restarts the device.
- Files locked by the system can keep a folder alive. The output shows Failed and the log names the folder; a restart usually clears the lock.
