# Remediate Windows LAPS

Intune Remediations script pair. The LAPS policy is assigned, but the password never reaches Entra ID or AD. Usually nobody notices until the password is needed.

## Files

| File | Purpose |
|---|---|
| `Detect-WindowsLAPS.ps1` | Looks for success events 10029 (Entra ID) and 10018 (AD) in the LAPS operational log and compares them with PasswordAgeDays plus `$GraceDays` (2). |
| `Remediate-WindowsLAPS.ps1` | Runs `Invoke-LapsPolicyProcessing`, then `Reset-LapsPassword` if the backup is still not confirmed. On failure it reports the latest LAPS error event. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-WindowsLAPS.ps1` as the detection script and `Remediate-WindowsLAPS.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Devices without a LAPS policy are reported as compliant.
