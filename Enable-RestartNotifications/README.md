# Enable Restart Notifications

Windows Update hides the pending restart toast for the first 24 hours by default. These scripts check the restart notification setting on existing devices and turn it on so users see the notification while there is still time to save work.

## Files

| File | Purpose |
|---|---|
| `Detect-RestartNotifications.ps1` | Reads `RestartNotificationsAllowed2` under the Windows Update UX settings key. Exits 1 when the value is missing or 0. |
| `Remediate-RestartNotifications.ps1` | Writes the value as 1, then reads it back and exits 0 only when the change is confirmed. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-RestartNotifications.ps1` as the detection script and `Remediate-RestartNotifications.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily, or once for the existing device fleet.
5. Assign to a pilot group first, confirm the setting in Settings > Windows Update > Advanced options, then widen the scope.

## Notes

- The toggle is documented as user controlled and is not an Intune policy value. A user can switch it back from Settings at any time.
- Devices below build 22621 report NotApplicable because the setting is documented from Windows 11 version 22H2.
- With a compliance deadline of 0 days the user still gets only the final 15 minute warning. This setting does not extend that deadline.
- No update is installed and no restart is triggered. The value applies at the next pending restart notification.
- If users report the toggle turning off again, find the source instead of only running the script more often.
