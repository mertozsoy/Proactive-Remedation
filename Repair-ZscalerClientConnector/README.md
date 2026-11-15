# Repair Zscaler Client Connector

The Zscaler Client Connector icon disappears from the taskbar and users lose internet or private application access because the ZSAService service has stopped. This pair checks the service state and startup mode, then starts the service and restores the automatic startup type when it was disabled.

## Files

| File | Purpose |
|---|---|
| `Detect-ZscalerClientConnector.ps1` | Reads the `ZSAService` state and startup mode. Exits 1 when the service is disabled or not running. Reports NotApplicable when the service is not installed. |
| `Remediate-ZscalerClientConnector.ps1` | Sets a disabled service back to Automatic, starts it, waits for the running state and checks the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-ZscalerClientConnector.ps1` as the detection script and `Remediate-ZscalerClientConnector.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Hourly.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- `ZSAService` is the main Zscaler Client Connector service and the watchdog for the other agent services. Confirm the name with `Get-Service ZSAService` on a device with the agent installed.
- The script only changes a Disabled startup type. A Manual or Automatic service is left as it is.
- Zscaler anti-tampering blocks non-admin users from changing the service. This script runs as SYSTEM, so a failed start points to the agent install or a Zscaler policy.
- The script does not restart the device, sign the user out or reinstall the agent. If the service stops again on every run, reinstall or upgrade the agent.
