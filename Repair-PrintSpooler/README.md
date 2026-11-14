# Repair Print Spooler

The Spooler service stops by itself after a driver fault, or a print job stays in the queue with an error flag and never leaves. In both cases the user cannot print and helpdesk restarts the service by hand. This pair checks the service and the queue, then starts the service and cancels the dead jobs.

## Files

| File | Purpose |
|---|---|
| `Detect-PrintSpooler.ps1` | Reads the `Spooler` service startup mode and state, then counts jobs in `Win32_PrintJob` that carry the error or blocked flag, or sit in spooling or printing state without progress for `$StuckMinutes`. |
| `Remediate-PrintSpooler.ps1` | Sets a disabled service back to Automatic, starts the service and waits for the running state, then cancels the stuck jobs and verifies the queue. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-PrintSpooler.ps1` as the detection script and `Remediate-PrintSpooler.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: every 4 hours, or daily if the fleet prints rarely.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Jobs in error or blocked state are cancelled. A job that is still spooling after `$StuckMinutes` with zero pages printed is treated as wedged and cancelled too.
- Set `$ClearStuckJobs = $false` to leave the queue untouched and only heal the service.
- `$PurgeSpoolFolder = $false` is the fallback that deletes the files under `C:\Windows\System32\spool\PRINTERS` while the service is stopped. Enable it only when job cancellation fails.
- A service disabled by policy is set back to Automatic once. If the policy wins again, the next run reports it and the policy needs to be fixed.
- The script starts the service but does not restart the device or sign the user out. A spooler that fails again right away points to a faulty print driver.
