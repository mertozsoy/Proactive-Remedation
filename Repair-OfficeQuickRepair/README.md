# Repair Office Quick Repair

Repeated Word, Excel or classic Outlook crashes can indicate damaged Office files. These scripts count crashes per application and can run the local Click-to-Run Quick Repair client without forcing Office apps to close.

## Files

| File | Purpose |
|---|---|
| `Detect-OfficeQuickRepair.ps1` | Flags three crashes of the same Office application within 24 hours. |
| `Remediate-OfficeQuickRepair.ps1` | Rechecks crashes, waits for closed Office apps and runs Quick Repair after approval. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload the detection and remediation scripts.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
4. Keep `$LookbackHours`, `$CrashThreshold` and `$CooldownHours` identical in both scripts. Defaults are 24 hours, three crashes per application and 72 hours between attempts.
5. Pilot the repair command on your Office build, then set `$EnableRemediation = $true`. Assign a pilot group and schedule daily during a maintenance window.

## Notes

- Repair starts disabled for approval. Open Office apps or a busy installer defer it; no process is forcibly closed.
- Only x86/x64 Click-to-Run Office is supported. MSI, ARM64 and new Outlook are excluded. Policies and update channels are not changed.
- Silent Quick Repair syntax is described in older Microsoft guidance; validate it against your deployed Office build.
- `RepairReturned` verifies client exit, service and file presence, not repair-worker completion or crash resolution. `Observing` counts only subsequent crashes.
- Failed or timed-out attempts block further repairs until reviewed. Keep the state file beside the log; reset it only after confirming no repair is running.
