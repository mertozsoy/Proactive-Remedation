# Repair First Logon Explorer

New or shared Windows devices can show stale desktop and taskbar state after the first sign-in. These scripts offer a one-time Explorer shell restart for recently created user profiles and verify that the replacement shell is running. They do not verify OneDrive sync or policy delivery.

## Files

| File | Purpose |
|---|---|
| `Detect-FirstLogonExplorer.ps1` | Checks profile age, completion state and the current user's Explorer shell. |
| `Remediate-FirstLogonExplorer.ps1` | Restarts that shell when enabled and saves completion after verification. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Upload the detection and remediation scripts listed above.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Keep the shared timing variables identical. Set `$EnableRemediation = $true` only after pilot approval and arranging a safe time for users.
5. Assign to a pilot device group. Schedule hourly while onboarding new profiles.

## Notes

- Restart is disabled by default: Explorer windows can close and file operations can be interrupted. Disabled remediation exits 1 without saving completion.
- Profile directory creation time within 48 hours is a heuristic, not proof of first logon. Restored profiles may be skipped; existing young profiles may qualify.
- A five-minute shell grace period does not prove policy or OneDrive readiness. Intune schedules are not logon triggers.
- Completion is stored in `%LOCALAPPDATA%\IntuneRemediations\FirstLogonExplorer\State.json` once per profile. Failed attempts have a 30-minute cooldown; profile deletion removes this protection.
- Only the unelevated current user's shell is targeted. No registry, policy, OneDrive, IME service, logoff or device restart changes are made.
