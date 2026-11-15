# Remediate Stale Group Policy

Domain joined devices refresh policy in the background every 90 minutes by default. On hybrid devices a VPN drop or a broken secure channel makes that refresh fail without a visible error. Drive maps, certificates and access rules then stay old for days. This pair measures the age of the last successful policy processing and forces a refresh when it is past a threshold.

## Files

| File | Purpose |
|---|---|
| `Detect-StaleGroupPolicy.ps1` | Reads the newest event 5016 in the Group Policy operational log and compares its age with `$MaxAgeDays`. Exits 0 when the device is not domain joined or the log is unavailable. |
| `Remediate-StaleGroupPolicy.ps1` | Runs `gpupdate /force /target:computer` and waits for a new success event. Reports the gpupdate exit code and the secure channel state when the refresh does not complete. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-StaleGroupPolicy.ps1` as the detection script and `Remediate-StaleGroupPolicy.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Low impact: one computer policy pass runs. A slow link can make it take several minutes, and no restart or sign-out is triggered.
- User policy is not refreshed by this script because it runs as SYSTEM. The logged-on user receives user policy at the next sign-in or the next background cycle.
- An offline device fails the refresh. The output then carries the secure channel state for triage.
- `$MaxAgeDays` defaults to 7 days, well above the 90 minute default refresh cycle.
- Devices that are not domain joined return NotApplicable.
