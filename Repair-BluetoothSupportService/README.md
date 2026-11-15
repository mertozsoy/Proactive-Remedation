# Repair Bluetooth Support Service

A Bluetooth headset pairs but Teams has no audio, or the device list stays empty because the Bluetooth Support Service (bthserv) is stopped or disabled. This pair checks the service on devices that have a Bluetooth radio, then restores the manual startup type and starts the service.

## Files

| File | Purpose |
|---|---|
| `Detect-BluetoothSupportService.ps1` | Reads the `bthserv` service state and startup mode and checks for a present Bluetooth radio. Exits 1 when the service is disabled or stopped. |
| `Remediate-BluetoothSupportService.ps1` | Sets a disabled service back to Manual, starts it and waits for the running state, then verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-BluetoothSupportService.ps1` as the detection script and `Remediate-BluetoothSupportService.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- The service starts but the Bluetooth radio stays under user control. If the user turned Bluetooth off, it stays off.
- `bthserv` is a trigger-start service, so Windows may stop it when no Bluetooth device is active. Set `$CheckStoppedState = $false` to flag only a disabled service.
- A missing service is reported as NotApplicable. That device needs a Bluetooth driver or stack repair.
- If a policy sets the service back to Disabled, fix the policy. The next run reports the state again.
- The script does not restart the device or sign the user out.
