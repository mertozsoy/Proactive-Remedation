# Remediate Secure Boot CA 2023

Intune Remediations script pair. The 2011 Secure Boot certificates expire starting June 2026. Devices that stay on them still boot, but stop getting boot level security fixes. This pair checks the move to the 2023 certificates and starts it when it has not begun.

## Files

| File | Purpose |
|---|---|
| `Detect-SecureBootCA2023.ps1` | Reads `UEFICA2023Status`, `UEFICA2023Error` and `AvailableUpdates`, checks the Secure Boot DB for Windows UEFI CA 2023 and the Secure-Boot-Update task. Legacy BIOS or Secure Boot off is reported as not applicable. |
| `Remediate-SecureBootCA2023.ps1` | Enables the Secure-Boot-Update task if disabled, sets `AvailableUpdates` to `0x5944` only when nothing is queued yet and runs the task. If `UEFICA2023Error` is present it stops and reports it. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-SecureBootCA2023.ps1` as the detection script and `Remediate-SecureBootCA2023.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Pilot per hardware model. Old firmware can trigger BitLocker recovery; update the BIOS first.
- The device needs one or two restarts to finish. The script never restarts the device.
