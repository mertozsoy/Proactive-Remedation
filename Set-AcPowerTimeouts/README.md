# Set AC Power Timeouts

Intune Remediations script pair. Meeting room and docked devices go to sleep after a few minutes and drop the presentation or wireless display. This pair keeps the plugged-in sleep and display timeouts of the active power plan at the values you set.

## Files

| File | Purpose |
|---|---|
| `Detect-AcPowerTimeouts.ps1` | Reads the AC values of "Sleep after" and "Turn off display after" from the active power plan through the `root\cimv2\power` WMI namespace and compares them with `$SleepTimeoutAcMinutes` (0 = never) and `$DisplayTimeoutAcMinutes` (60). |
| `Remediate-AcPowerTimeouts.ps1` | Writes the target values to the active plan with `powercfg /setacvalueindex`, reactivates the plan and reads the values back. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-AcPowerTimeouts.ps1` as the detection script and `Remediate-AcPowerTimeouts.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Only plugged-in (AC) values are changed. Battery values are left alone.
- If a setting is delivered by policy (`HKLM\SOFTWARE\Policies\Microsoft\Power\PowerSettings`), it is reported as `Policy` and not changed.
- Assign only to the device group that needs these values (meeting rooms, docked devices). Users can still change the values in Settings; the next run sets them back.
- No text output of powercfg is parsed, so the scripts work on any display language.
