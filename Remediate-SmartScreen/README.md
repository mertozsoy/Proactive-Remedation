# Remediate SmartScreen

Local administrators can turn off App and browser control from Windows Security. The change usually stays on the device while Intune has no matching setting, so SmartScreen stops checking downloaded files and Edge loses the same protection. These scripts read the effective state and turn SmartScreen back on through the policy value.

## Files

| File | Purpose |
|---|---|
| `Detect-SmartScreen.ps1` | Reads the EnableSmartScreen policy value, the device value and the Edge SmartScreenEnabled policy. Exits 1 when SmartScreen is off. |
| `Remediate-SmartScreen.ps1` | Writes EnableSmartScreen=1 and turns the Edge policy back on. A disabled policy value is preserved unless the opt-in variable is set. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-SmartScreen.ps1` as detection and `Remediate-SmartScreen.ps1` as remediation.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
4. Schedule: Daily.
5. Assign to a pilot group first and check App and browser control on a few devices before widening the scope.

## Notes

- The policy value wins over the per-device value. Writing EnableSmartScreen=1 applies SmartScreen to all users and blocks the toggle in Windows Security.
- Values already set to 0 count as managed. `$OverrideDisabledPolicy` and `$EnforceEdgePolicy` must be turned on for the script to replace them, and the old key is exported to `%ProgramData%\IntuneRemediations\Backup` first.
- The warning level (Warn or Block) is not changed. Only the on or off state is enforced.
- Server editions exit 0 as NotApplicable. Logs: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT_SmartScreen.log`.
- No restart is requested. Edge reads the policy at the next start.
