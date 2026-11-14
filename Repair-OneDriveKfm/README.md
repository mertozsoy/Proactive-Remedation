# Repair OneDrive KFM

Intune Remediations script pair. The KFMSilentOptIn policy shows as applied, but Desktop and Documents stay in the local profile until OneDrive is restarted. This pair finds users whose known folders are still local and restarts the sync app so it evaluates the policy again.

## Files

| File | Purpose |
|---|---|
| `Detect-OneDriveKfm.ps1` | Runs as the user. Reads `KFMSilentOptIn` and the per folder values from `HKLM\SOFTWARE\Policies\Microsoft\OneDrive`, then compares the Desktop, Documents and Pictures paths with `$env:OneDriveCommercial`. |
| `Remediate-OneDriveKfm.ps1` | Shuts OneDrive down with `/shutdown`, starts it with `/background` and waits up to `$WaitSeconds` for the folders to move. Gives up after `$MaxAttempts` restarts and reports `ManualCheck`. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-OneDriveKfm.ps1` as the detection script and `Remediate-OneDriveKfm.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Must run with the logged-on credentials. Folder paths and the OneDrive account are per user.
- Only OneDrive is restarted. Explorer and user applications are not closed.
- If the "Prohibit User from manually redirecting Profile Folders" policy is enabled, KFM cannot work. The scripts report `Blocker=DisablePersonalDirChange` and do nothing.
- The attempt counter is stored in `HKCU\Software\IntuneRemediations\OneDriveKfm` and is cleared when the folders are redirected.
- Log file: `%LOCALAPPDATA%\IntuneRemediations\Logs\IRT_OneDriveKfm.log`.
