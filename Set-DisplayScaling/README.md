# Set Display Scaling

When Windows is left in single-scale mode every display gets the laptop scale, so a docked external monitor keeps 125% and the user cannot make it readable. These scripts find the forced values in the current user hive and put Windows back into per-monitor scaling.

## Files

| File | Purpose |
|---|---|
| `Detect-DisplayScaling.ps1` | Reads `Win8DpiScaling`, `DesktopDPIOverride` and `LogPixels` and reports drift. |
| `Remediate-DisplayScaling.ps1` | Backs up the key, restores per-monitor mode, resets the scale cache and verifies the values. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Select both scripts. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** unless the scripts are signed.
3. Assign to a pilot user group and run weekly. Ask a pilot user to sign out and back in with the dock connected.
4. Check the device status output after the next run.

## Notes

- Documented values: `Win8DpiScaling` 0 means a scale per display, `DesktopDPIOverride` 0 means the default scale of each display.
- The desktop key and the per-monitor scale cache are exported to `%LOCALAPPDATA%\IntuneRemediations\Backup` before any write.
- The cache is removed so Windows detects the recommended scale for the dock again. Keep it with `$ResetPerMonitorCache = $false`.
- Nothing signs the user out. The new mode is active after the next sign-in and after the dock reconnects.
- If a Group Policy preference or an image script writes these values again, detection goes back to Drift.
