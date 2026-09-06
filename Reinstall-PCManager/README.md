# Reinstall Microsoft PC Manager

Intune Proactive Remediation pair that forces a **reinstall of Microsoft PC Manager** (Microsoft Store app) on every run, using the same always-remediate pattern as `Reinstall-WinGet`. Based on the community pattern from Jorgen Nilsson (ccmexec.com).

## Files

| File | Purpose |
|---|---|
| `Detect-PCManager.ps1` | Always exits `1` (always non-compliant), forcing remediation to run on every scheduled cycle. |
| `Remediate-PCManager.ps1` | Removes the `Microsoft.MicrosoftPCManager` Appx package for all users, clears the app's tracking keys under the IME `Win32Apps` registry path (by Intune App ID), then schedules an IME service restart after a 160-second delay so the reinstall picks up cleanly. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context**.
4. Requires a corresponding **Win32/Store app assignment** for PC Manager targeting the same devices.

## Notes

- `$AppID` is the Intune Win32 app ID for your PC Manager assignment, not a secret — replace it with the app ID from your own tenant before deploying.
- Use with caution: this always-remediate pattern causes the script to run its full remediation logic on every single check-in cycle.
