# Repair Click-to-Run Service

Word, Excel and Outlook stop opening because the Microsoft Office Click-to-Run service (ClickToRunSvc) is stopped or disabled. This pair checks the service state and startup mode, then starts the service and restores the automatic startup type when it was disabled.

## Files

| File | Purpose |
|---|---|
| `Detect-ClickToRunService.ps1` | Reads the `ClickToRunSvc` state, startup mode and reported Office version. Exits 1 when the service is disabled or not running. Reports NotApplicable when the service is not installed. |
| `Remediate-ClickToRunService.ps1` | Sets a disabled service back to Automatic, starts it, waits for the running state and verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-ClickToRunService.ps1` as the detection script and `Remediate-ClickToRunService.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily, or hourly while a support wave is open.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- `ClickToRunSvc` is the service that Click-to-Run Office registers. A missing service usually means Office on that device is not a Click-to-Run install, so the detection reports NotApplicable.
- Only a Disabled startup type is changed. A Manual service is left alone unless `$UpgradeManualStartMode` is set to `$true`.
- When a policy or a cleanup script keeps disabling the service, the next policy refresh wins again. Fix the source policy instead of relying on repeated runs.
- A service that fails to start points to the Office installation. Quick Repair or Online Repair is the next step.
- The script does not restart the device, close Office windows or sign the user out.
