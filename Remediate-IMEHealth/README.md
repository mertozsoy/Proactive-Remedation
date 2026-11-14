# Remediate IME Health

Intune Remediations script pair. The Intune Management Extension can stay Running while it no longer processes anything, and Win32 apps and scripts quietly stop arriving. This pair finds that state and restarts the agent safely.

## Files

| File | Purpose |
|---|---|
| `Detect-IMEHealth.ps1` | Checks the service start type, its state and the age of `IntuneManagementExtension.log`. The log is considered stale after `$MaxLogAgeHours` (12). |
| `Remediate-IMEHealth.ps1` | Sets the start type to Automatic and creates a one time SYSTEM task that restarts IME two minutes later and then deletes itself. A direct restart would stop the remediation before it reports back. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-IMEHealth.ps1` as the detection script and `Remediate-IMEHealth.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Every 8 hours.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- If IME is fully stopped, no remediation can run on that device. A reboot or a platform script is needed in that case.
