# Enable Teams Outlook Notifications

Intune Remediations script pair. A user can turn off notifications for Teams or Outlook from Windows Settings, or the master notification switch gets turned off, and nobody notices until a message is missed. This pair reads the per-user notification settings and turns them back on.

## Files

| File | Purpose |
|---|---|
| `Detect-TeamsOutlookNotifications.ps1` | Runs as the user. Reads `ToastEnabled` under `HKCU\...\PushNotifications` and the `Enabled` value of every key under `HKCU\...\Notifications\Settings` that matches `$AppPatterns`. Flags a policy block from `NoToastApplicationNotification`. |
| `Remediate-TeamsOutlookNotifications.ps1` | Backs up each changed key with `reg export`, sets `ToastEnabled` to 1 and the app `Enabled` value to 1. Skips everything when a policy blocks toasts. Checks the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-TeamsOutlookNotifications.ps1` as the detection script and `Remediate-TeamsOutlookNotifications.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- `$AppPatterns` matches the Teams and Outlook app IDs. Add a pattern if your tenant uses another notification sender name.
- If `NoToastApplicationNotification` is set by policy, both scripts report `Blocked` and change nothing. Fix the policy instead.
- Windows 11 can cache the old state. The script sets the value but the app may need a sign-out or a manual toggle in Settings before the first toast appears.
- `$RestartPushService` is off by default because restarting the Windows Push Notifications User Service needs more rights than a standard user has.
- Old values are exported to `%ProgramData%\IntuneRemediations\Backup` or `%LOCALAPPDATA%\IntuneRemediations\Backup` before any write.
