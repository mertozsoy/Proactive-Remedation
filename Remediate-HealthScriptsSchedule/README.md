# Remediate Health Scripts Schedule

Remediations can run once and then stop on some devices. The IME keeps a LastExecution value for each remediation under SideCarPolicies. When that value is unreadable, in the future, or very old, the next run is never calculated. These scripts find those entries, back up the state and clear the values so the schedule is rebuilt.

## Files

| File | Purpose |
|---|---|
| `Detect-HealthScriptsSchedule.ps1` | Reads LastExecution values and reports entries that cannot be parsed, sit in the future, or are older than the stale limit. |
| `Remediate-HealthScriptsSchedule.ps1` | Exports the state with reg export, removes the flagged LastExecution values, rescans and starts the enrollment check-in task. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-HealthScriptsSchedule.ps1` and `Remediate-HealthScriptsSchedule.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Schedule: Daily.
5. Assign to a pilot group before widening the scope.

## Notes

- Medium impact: flagged entries are treated as never run. Recurring scripts run on their next schedule and a one-time script that ran long ago may run again.
- The state is exported to `%ProgramData%\IntuneRemediations\Backup` before any value is removed.
- The IME service is not restarted because these scripts run inside IME. The new schedule applies at the next policy retrieval or after a reboot.
- Set `$MaxAgeDays` to match the longest remediation schedule in the tenant. Set `$ScriptIdFilter` to limit the reset to given script IDs.
- `$EnableRemediation = $false` by default because the IME execution state under SideCarPolicies is not documented by Microsoft. Test on a pilot group before enabling it. Set `$TriggerCheckIn = $false` to skip the check-in task.
