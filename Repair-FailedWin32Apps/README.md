# Repair Failed Win32 Apps

Intune Remediations script pair. A required Win32 app that fails is not retried by IME until the 24 hour retry timer (GRS) expires. This pair finds failed apps in the IME state and clears that state so the install is retried on the next app check-in.

## Files

| File | Purpose |
|---|---|
| `Detect-FailedWin32Apps.ps1` | Reads `EnforcementStateMessage` under the IME `Win32Apps` key for every user and lists apps with a non-zero error code. `$AppIdFilter` limits the check to given app IDs, `$IgnoredErrorCodes` skips reboot codes. |
| `Remediate-FailedWin32Apps.ps1` | Deletes the state key of each failed app and the matching GRS entry, then checks that no failed state is left. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-FailedWin32Apps.ps1` as the detection script and `Remediate-FailedWin32Apps.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Medium impact: the app installer runs again on the device. Start with a pilot group.
- The script does not restart the IME service because the script itself runs inside IME. The retry happens on the next app check-in (about every 60 minutes) or after a restart.
- An app that fails for a real reason (bad install command, missing dependency) will fail again. Use the error code in the output to find those.
- Set `$AppIdFilter` to the app IDs from the Intune portal URL if only some apps should be retried.
