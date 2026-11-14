# Remove Spotlight Desktop Icon

Intune Remediations script pair. When Windows Spotlight is the desktop background, Windows adds a "Learn about this picture" icon that users cannot delete. This pair hides that icon for the signed-in user and keeps Spotlight itself running.

## Files

| File | Purpose |
|---|---|
| `Detect-SpotlightDesktopIcon.ps1` | Checks the `{2cc5ca98-6485-489a-920e-b3e88a6ccce3}` value under `HKCU\...\Explorer\HideDesktopIcons\NewStartPanel`. Returns NotApplicable when Spotlight on the desktop is turned off by the CloudContent policy. |
| `Remediate-SpotlightDesktopIcon.ps1` | Sets the value to 1 (DWORD), refreshes the desktop with `SHChangeNotify` and verifies the value. Explorer is not restarted. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-SpotlightDesktopIcon.ps1` as the detection script and `Remediate-SpotlightDesktopIcon.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- The setting is per user. The scripts run in the user context and write logs to `%LOCALAPPDATA%\IntuneRemediations\Logs\IRT_SpotlightDesktopIcon.log`.
- If the icon is still visible after remediation, pressing F5 on the desktop or signing out and back in removes it.
- To turn off Spotlight on the desktop completely, use the `Experience/AllowSpotlightCollection` policy instead.
