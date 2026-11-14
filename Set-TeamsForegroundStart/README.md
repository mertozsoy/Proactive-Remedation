# Set Teams Foreground Start

The new Teams client can be left with open in background enabled, so it starts without a window and users open tickets saying Teams did not launch. These scripts read the per-user Teams settings file and pull the value back to the foreground start.

## Files

| File | Purpose |
|---|---|
| `Detect-TeamsForegroundStart.ps1` | Reads `open_app_in_background` from the new Teams settings file and reports drift. |
| `Remediate-TeamsForegroundStart.ps1` | Backs up the settings file, sets the value and verifies it. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Select both scripts. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** unless the scripts are signed.
3. Assign to a pilot user group and run daily. Confirm that Teams opens with its main window after the next sign-in.
4. Set `$ExpectedBackgroundStart = $true` in both scripts if the standard is the opposite.

## Notes

- The setting lives in `%LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\app_settings.json` and is per user. Scripts run in user context.
- A running `ms-teams` process owns the file and writes its own copy on exit. The remediation exits 1 with Deferred instead of stopping the app.
- The original file is copied to `%LOCALAPPDATA%\IntuneRemediations\Backup` before any write.
- Teams autostart is a separate startup task and is not touched here, so notifications keep working when Teams is started.
- Reads only the value; no policy key is used, so a Teams update can change it again and the next schedule re-applies it.
