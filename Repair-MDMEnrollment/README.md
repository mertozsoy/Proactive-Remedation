# Repair MDM Enrollment

A hybrid Entra joined device can stay outside Intune when the Group Policy auto-enrollment task never runs. These scripts find that state and start the enrollment client task so enrollment is attempted again.

## Files

| File | Purpose |
|---|---|
| `Detect-MDMEnrollment.ps1` | Checks the domain join and Entra join state and looks for an active Intune enrollment under the Enrollments key. Reports the auto-enrollment task state when the device is not enrolled. |
| `Remediate-MDMEnrollment.ps1` | Enables the auto-enrollment task when it is disabled, starts it and waits for the Intune enrollment key within a bounded window. |

## Deployment (Intune)

1. Confirm that the Group Policy **Enable automatic MDM enrollment using default Microsoft Entra credentials** is applied to the device and that MDM user scope covers the device users.
2. Go to **Devices > Scripts and remediations > Remediations > Create**.
3. Upload `Detect-MDMEnrollment.ps1` as the detection script and `Remediate-MDMEnrollment.ps1` as the remediation script.
4. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot group first and schedule daily until the devices are enrolled.

## Notes

- Medium impact: the scripts start the Microsoft enrollment task on the device. Start with a pilot group.
- The scripts do not create the task. If it is missing, Group Policy is not applied and the remediation reports Failed.
- The task name is localized on non-English Windows. Set `$AutoEnrollTaskNameMatch` to the local name in both scripts when the task is reported as Missing.
- The device must be domain joined and Entra joined. MDM user scope must be All and the user needs an Intune license.
- The wait window is 90 seconds. A slow enrollment can finish after the run. Failures are logged as event 76 under DeviceManagement-Enterprise-Diagnostic-Provider.
