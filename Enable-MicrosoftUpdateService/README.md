# Enable Microsoft Update Service

A device can keep scanning only Windows updates after the update ring allows Microsoft product updates. Office and driver updates never appear because the Microsoft Update service is not registered with the Windows Update Agent. This pair reads the policy and the Windows Update setting, registers the service and verifies the result.

## Files

| File | Purpose |
|---|---|
| `Detect-MicrosoftUpdateService.ps1` | Reads the Microsoft product updates policy and the Windows Update UX value, then checks the Windows Update Agent service list for the Microsoft Update service. |
| `Remediate-MicrosoftUpdateService.ps1` | Sets the UX value to 1 and registers the Microsoft Update service with Automatic Updates. Leaves a blocking policy unchanged. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-MicrosoftUpdateService.ps1` as the detection script and `Remediate-MicrosoftUpdateService.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, then widen the scope.

## Notes

- A policy that sets Microsoft product updates to Block is reported and left unchanged.
- Windows ships with Microsoft Update off. Assign this only to devices that should receive Office and driver updates.
- No restart, no service restart and no update installation. Set `$TriggerScan` to `$true` to start a scan after registration.
- The service list is read through `Microsoft.Update.ServiceManager`; Windows Update service registry keys are not edited directly.
- Logs: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT_MicrosoftUpdateService.log`.
