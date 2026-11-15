# Remove Legacy Remote Desktop Client

The Remote Desktop app for Windows from the Microsoft Store is no longer supported, and support for the MSI client named Remote Desktop ended in March 2026. Devices often keep one or both versions after users move to Windows App. These scripts find every remaining installation and remove it.

## Files

| File | Purpose |
|---|---|
| `Detect-LegacyRemoteDesktopClient.ps1` | Counts Store app registrations, provisioned entries and MSI client entries. Returns 1 when any remain. |
| `Remediate-LegacyRemoteDesktopClient.ps1` | Removes provisioning, all-user registrations and the MSI client, then verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-LegacyRemoteDesktopClient.ps1` and `Remediate-LegacyRemoteDesktopClient.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
4. Assign to a pilot device group that already uses Windows App. Schedule daily.
5. Check the device status report before widening the assignment.

## Notes

- The Store app and the MSI client both use the display name Remote Desktop. The built-in Remote Desktop Connection client is not touched.
- Windows App on Windows cannot connect to Remote Desktop Services. `$OnlyWhenWindowsAppInstalled = $true` by default, so the legacy client is only removed when Windows App is already installed. Keep the legacy client on devices that still need it.
- Per-user MSI entries are read from loaded user hives. Profiles that are not loaded are not covered in that run.
- Removal is deferred while a Remote Desktop process is running. No process is stopped, no user is signed out and no restart is initiated.
- Windows clients only. Provisioned removal prevents the app from returning for new user profiles.
