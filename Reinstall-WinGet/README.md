# Reinstall WinGet (App Installer)

Intune Proactive Remediation pair that forces a **reinstall of WinGet (Microsoft.DesktopAppInstaller)** on every run. This is the standard "always remediate" pattern used to force Intune to redeploy a Win32 app assignment: detection always reports non-compliant, and remediation removes the app plus its Intune Management Extension (IME) tracking registry so Intune reinstalls it from the assigned Win32 app package.

Based on the community pattern from Jorgen Nilsson (ccmexec.com).

## Files

| File | Purpose |
|---|---|
| `Detect-WinGet.ps1` | Always exits `1` (always non-compliant), forcing remediation to run on every scheduled cycle. |
| `Remediate-WinGet.ps1` | Removes the `Microsoft.DesktopAppInstaller` Appx package for all users, clears the app's tracking keys under the IME `Win32Apps` registry path (by Intune App ID), then schedules an IME service restart after a 160-second delay so the reinstall picks up cleanly. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context**.
4. Requires a corresponding **Win32 app assignment** for WinGet/App Installer targeting the same devices — this remediation only clears the old install so Intune's own app assignment reinstalls it.

## Notes

- `$AppID` is the **Intune Win32 app ID** for your WinGet package assignment, not a secret — replace it with the app ID from your own tenant's Intune app registration before deploying.
- Use with caution: this always-remediate pattern causes the script to run its full remediation logic on every single check-in cycle.
