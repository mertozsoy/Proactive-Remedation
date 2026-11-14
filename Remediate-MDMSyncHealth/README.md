# Remediate MDM Sync Health

Intune Remediations script pair. The MDM channel that brings configuration profiles and compliance can break while IME keeps working. The usual causes are a disabled dmwappushservice or disabled enrollment tasks.

## Files

| File | Purpose |
|---|---|
| `Detect-MDMSyncHealth.ps1` | Checks the last successful OMA-DM session, the dmwappushservice start type and the PushLaunch task of the Intune enrollment. Exits `1` when the last sync is older than `$MaxHoursSinceSync` (24) or a prerequisite is broken. |
| `Remediate-MDMSyncHealth.ps1` | Sets dmwappushservice back to Manual, enables and runs the PushLaunch task. Falls back to the Schedule #3 task created by the enrollment client. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-MDMSyncHealth.ps1` as the detection script and `Remediate-MDMSyncHealth.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Every 8 hours.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Devices without an Intune MDM enrollment are reported and not re-enrolled.
