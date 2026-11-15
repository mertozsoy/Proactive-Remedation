# Remove WER Crash Reports

An app that crashes in a loop writes a Windows Error Reporting entry for every crash. The report queue under C:\ProgramData\Microsoft\Windows\WER and the per-user CrashDumps folders grow until the system disk is full. This script pair measures those folders and deletes items that are past the age limit when the size limit is crossed.

## Files

| File | Purpose |
|---|---|
| `Detect-WerCrashReports.ps1` | Measures the WER report queue, the archive and every profile CrashDumps folder. `$SizeLimitMB`, `$ExpiredSizeLimitMB` and `$MinAgeDays` set the limits. |
| `Remediate-WerCrashReports.ps1` | Deletes queue, archive and dump items older than `$MinAgeDays`, then measures again. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Upload `Detect-WerCrashReports.ps1` as the detection script and `Remediate-WerCrashReports.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**.
4. Run script in 64-bit PowerShell: **Yes**. Schedule: Daily.
5. Keep the limits and `$IncludeUserProfiles` identical in both scripts. Assign to a pilot group first.

## Notes

- Cleanup is limited to the WER report queue, the WER archive and the CrashDumps folder of each profile. The folders themselves are kept.
- Defaults are 1024 MB total, 256 MB of expired items and 7 days of age. Set `$RemoveReports = $false` to report without deleting.
- Old reports are support evidence. Raise `$MinAgeDays` if crash data has to stay available longer.
- A file held open by Windows Error Reporting is skipped and counted in the output. The next run retries it.
- The script never restarts the device or the Intune Management Extension service.
