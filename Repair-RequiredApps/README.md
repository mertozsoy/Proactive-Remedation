# Repair Required Apps

Intune Remediations script pair. When a user uninstalls a Required Win32 app, the Intune Management Extension can keep its cached "installed" state and the app does not come back. This pair checks a short list of business critical apps on the device and clears the cached state of the missing ones, so the Required assignment is evaluated again.

## Files

| File | Purpose |
|---|---|
| `Detect-RequiredApps.ps1` | Tests every app in `$RequiredApps` with a file path or an uninstall display name. Flags the app when it is missing and a state key still exists under `Win32Apps`. |
| `Remediate-RequiredApps.ps1` | Deletes the `Win32Apps\<user>\<AppId>_*` state keys and the matching `GRS` entries of the missing apps, then verifies they are gone. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-RequiredApps.ps1` as the detection script and `Remediate-RequiredApps.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Fill `$RequiredApps` in both scripts with the same values. Example: `@{ Name = 'VPN Client'; AppId = '<Intune app ID>'; DetectPath = 'C:\Program Files\Vendor\client.exe' }`. Use `DisplayName = 'Vendor Client*'` instead of `DetectPath` to match the uninstall entry.
- The app ID is the GUID in the app URL in the Intune admin center.
- With an empty list the detection returns `NotApplicable`.
- The script does not install anything and does not restart the Intune Management Extension service. The app returns on the next IME app check-in.
- The `Win32Apps` and `GRS` registry layout is not documented by Microsoft. Test on a pilot group after IME updates.
- Keep the list short. This is meant for a few critical apps, not for every assignment.
