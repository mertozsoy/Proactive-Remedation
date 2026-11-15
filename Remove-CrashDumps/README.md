# Remove Crash Dumps

Intune Remediations script pair. A stop error leaves MEMORY.DMP, minidumps and live kernel reports on the system drive and nothing deletes them afterwards. On devices that crash often these files reach tens of GB and feature updates fail with low disk space, so this pair removes the ones older than the age limit.

## Files

| File | Purpose |
|---|---|
| `Detect-CrashDumps.ps1` | Reads `DumpFile` and `MinidumpDir` from `CrashControl` and the `LiveKernelReports` path, then sizes every `*.dmp` file. Exits 1 when files older than `$MinimumAgeDays` reach `$ThresholdMB`. |
| `Remediate-CrashDumps.ps1` | Deletes the eligible dump files, logs each path with its size and re-scans the same locations. `$RemoveFiles = $false` turns it into a report only run. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Upload `Detect-CrashDumps.ps1` as the detection script and `Remediate-CrashDumps.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the reported sizes, then widen the scope.

## Notes

- Cleanup is on by default but limited to `*.dmp` files older than `$MinimumAgeDays` (7 days). Set `$RemoveFiles` to `$false` to report only.
- Dumps are the main evidence for a stop error. Keep the age window longer than your support case turnaround.
- Paths come from `CrashControl`, so a redirected `DumpFile` or `MinidumpDir` is covered. `DedicatedDumpFile` is never touched.
- `CrashDumpEnabled` is reported, not changed. With the Complete type MEMORY.DMP grows with the amount of RAM.
- `$ThresholdMB` decides when detection exits 1. Below that size the device stays healthy.
