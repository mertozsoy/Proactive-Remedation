# Remediate Teams Meeting Add-in

Intune Remediations script pair. The Teams Meeting button disappears from classic Outlook, or the add-in looks enabled but meetings cannot be created. This pair checks the add-in for the signed in user and repairs it without admin rights.

## Files

| File | Purpose |
|---|---|
| `Detect-TeamsMeetingAddin.ps1` | Finds classic Outlook and its bitness, the installed add-in versions, LoadBehavior, the COM registration and the Outlook hard disable list. Policy blocks (AddinList, trusted add-ins) are reported only. Devices without classic Outlook return NOT-APPLICABLE. |
| `Remediate-TeamsMeetingAddin.ps1` | When Outlook is closed, sets LoadBehavior to `3` (unless policy owns it) and registers the matching `Microsoft.Teams.AddinLoader.dll` with `regsvr32 /n /i:user`. The DLL signature is checked first. If Outlook is open, nothing is changed and the fix waits for the next run. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-TeamsMeetingAddin.ps1` as the detection script and `Remediate-TeamsMeetingAddin.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily, preferably in the morning after sign in.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Requires new Teams, which installs the add-in into the user profile.
- The old 1.23 add-in is reported, not removed. Removing it needs admin rights.
- Log: `%LOCALAPPDATA%\IntuneRemediations\Logs\IRT-REM-002.log`
