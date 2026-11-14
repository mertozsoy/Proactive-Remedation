# Remove Stale Printer Queues

Retired print server connections and old Universal Print queues can remain visible after migration. These scripts match an explicit retirement list, remove matching queues in the signed-in user's context and verify the result.

## Files

| File | Purpose |
|---|---|
| `Detect-StalePrinterQueues.ps1` | Flags queues matching retired UNC server names or exact queue identities. |
| `Remediate-StalePrinterQueues.ps1` | Checks jobs, removes approved queues with Remove-Printer and verifies absence. |

## Deployment (Intune)

1. Set `$RetiredPrintServers` in both scripts to retired host names, for example `@('print-old.contoso.com')`. Include short names separately if used.
2. For individual queues, including Universal Print, set `$RetiredQueues` in both scripts using actual Get-Printer properties: `@(@{ Name = 'Retired queue'; PortName = 'actual port'; DriverName = 'actual driver'; Type = 'Local' })`. Keep both target lists identical.
3. Withdraw the corresponding GPO, Intune and other printer deployment assignments. Confirm this by setting `$SourceAssignmentsRemoved = $true` in remediation.
4. Go to **Devices > Scripts and remediations > Remediations > Create**. Upload the matching detection and remediation files.
5. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** unless signed through your normal process.
6. Assign to a pilot user group and schedule daily. Review results before expanding.

## Notes

- Empty target lists return NotApplicable. Offline status alone never selects a queue.
- Assignment ownership is not inferred. Removal stays blocked until source withdrawal is confirmed.
- Visible jobs always block removal. `$AllowUnverifiedJobRemoval = $false` protects unreadable queues; enabling it can lose unseen jobs. Job inspection is not an atomic lock against new submissions.
- Runs without elevation; permission failures remain Failed. No drivers, ports, server queues or registry entries are deleted; ghosts absent from Get-Printer are outside scope.
- Removing the default queue may change the default printer. Output and logs contain counts and error codes, not queue names or document details.
