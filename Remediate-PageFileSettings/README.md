# Remediate Page File Settings

Old tuning scripts sometimes disable the page file or pin it to a small fixed size. Applications then fail with out of memory errors and Windows cannot write a crash dump. This pair reads the page file configuration and turns automatic management back on.

## Files

| File | Purpose |
|---|---|
| `Detect-PageFileSettings.ps1` | Reads `AutomaticManagedPagefile` from `Win32_ComputerSystem`, the configured page files and the `PagingFiles` registry value. Exits 1 when automatic management is off or no page file is configured. |
| `Remediate-PageFileSettings.ps1` | Backs up the memory management key, sets `AutomaticManagedPagefile` to true through CIM and reads the setting back. Exits 0 when the system managed state is confirmed. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-PageFileSettings.ps1` as the detection script and `Remediate-PageFileSettings.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- The new page file size takes effect after a restart. The script never restarts the device.
- Any fixed or disabled page file is reported as drift. Exclude devices where a fixed page file is intentional.
- The memory management key is exported to `%ProgramData%\IntuneRemediations\Backup` before the change.
- `$SetAutomaticMemoryDump` is off by default. Set it to `$true` to move a disabled dump setting to automatic while the page file is restored.
- At least `$MinimumFreeSpaceGB` free space is required on the system drive. Below that the script only reports.
