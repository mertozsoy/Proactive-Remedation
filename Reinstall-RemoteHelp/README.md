# Reinstall Remote Help

Intune Proactive Remediation pair that forces a **reinstall of the Remote Help** app on every run, using the same always-remediate pattern as `Reinstall-WinGet`. Based on the community pattern from Jorgen Nilsson (ccmexec.com).

## Files

| File | Purpose |
|---|---|
| `Detect-RemoteHelp.ps1` | Always exits `1` (always non-compliant), forcing remediation to run on every scheduled cycle. |
| `Remediate-RemoteHelp.ps1` | Silently uninstalls Remote Help via `msiexec.exe /x <MSIProductCode> /quiet /noreboot`, clears the app's tracking keys under the IME `Win32Apps` registry path (by Intune App ID), then schedules an IME service restart after a 160-second delay so the reinstall picks up cleanly. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context**.
4. Requires a corresponding **Win32 app assignment** for Remote Help targeting the same devices.
5. **Verify `$MSIProductCode`** against the Remote Help version deployed in your tenant before use — this value changes between Remote Help releases (find it via `Get-ChildItem` on the uninstall registry keys on a device with Remote Help installed, or from your own Win32 app package).

## Notes

- `$AppID` and `$MSIProductCode` are Intune/MSI identifiers, not secrets — but `$MSIProductCode` is version-specific, so confirm it matches your currently deployed Remote Help build.
- Use with caution: this always-remediate pattern causes the script to run its full remediation logic on every single check-in cycle.
