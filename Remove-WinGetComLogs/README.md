# Remove WinGet COM Logs

Intune Remediations script pair. A WinGet logging bug writes WinGetCOM log files into `C:\Windows\Temp\WinGet` that grow to several GB each and fill the system disk. This pair measures that folder, then deletes the old log files once the size limit is crossed.

## Files

| File | Purpose |
|---|---|
| `Detect-WinGetComLogs.ps1` | Measures the WinGet temp folder and the largest log file. `$FolderSizeLimitMB` and `$SingleFileLimitMB` set the limits. |
| `Remediate-WinGetComLogs.ps1` | Deletes `.txt` and `.log` files under the folder that are older than `$MinFileAgeMinutes`, then measures again. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-WinGetComLogs.ps1` as the detection script and `Remediate-WinGetComLogs.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**.
4. Run script in 64-bit PowerShell: **Yes**. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Only files inside `C:\Windows\Temp\WinGet` are touched. The folder itself is kept.
- Files written in the last 15 minutes are skipped so an active WinGet run keeps its log.
- A file held open by another process stays in place and is counted as skipped. The next run retries it.
- The script does not restart the Intune Management Extension service.
- Log growth comes from the WinGet client. Cleaning controls disk usage but does not remove the cause.
