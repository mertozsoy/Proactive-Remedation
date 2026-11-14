# Set Teams Auto Start

The new Teams client is an MSIX app with a startup task, and that task can stay off after a reset, a profile rebuild or a user toggle. Users then miss chats and meeting reminders because Teams never starts. These scripts read the per-user startup task state and turn it back on.

## Files

| File | Purpose |
|---|---|
| `Detect-TeamsAutoStart.ps1` | Reads the `TeamsTfwStartupTask` state and reports drift or a policy block. |
| `Remediate-TeamsAutoStart.ps1` | Backs up the key with `reg export`, enables the startup task and verifies the value. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Select both scripts. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** unless the scripts are signed.
3. Assign to a pilot user group and run once a day. Sign out and back in on a test device to confirm that Teams starts with Windows.
4. Keep the same scripts in a second assignment if some users must have autostart off, and exclude those users.

## Notes

- The state is per user under `HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask`.
- State 2 and 4 mean enabled, 0 and 1 mean disabled, 3 means a policy disabled the task.
- Startup tasks are blocked when `EnableFullTrustStartupTasks`, `EnableUwpStartupTasks`, `SupportFullTrustStartupTasks` or `SupportUwpStartupTasks` is 0 under `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System`. The scripts report this instead of changing it.
- The change applies at the next sign-in. Teams does not need to be restarted and is never closed by the script.
- The open in background setting is a separate value and is not touched here.
