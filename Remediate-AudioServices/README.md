# Remediate Audio Services

Intune Remediations script pair. When the Windows Audio or Windows Audio Endpoint Builder service is stopped or disabled, the device loses sound and the output device list stays empty. This pair checks both services, restores the startup type and starts them again without a restart.

## Files

| File | Purpose |
|---|---|
| `Detect-AudioServices.ps1` | Reads both services from CIM and counts present audio endpoints. `$AudioServices` and `$CheckEndpoints` control the scope. Exits 1 when a service is disabled or not running. |
| `Remediate-AudioServices.ps1` | Backs up the service key, sets a disabled service to Automatic, starts both services and verifies that they run. Services managed by a service security policy are reported and skipped. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-AudioServices.ps1` as the detection script and `Remediate-AudioServices.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily. Use a shorter interval only for a pilot group with reported audio problems.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Starting a stopped service does not interrupt a running session. Only the optional endpoint builder restart causes a few seconds of silence.
- `$RestartEndpointBuilder` is `$false` by default. Set it to `$true` to restart the endpoint builder when no audio endpoint is present.
- Services set under Computer Configuration > Windows Settings > Security Settings > System Services are reported as policy managed and left alone.
- A driver fault or a missing audio device is not repaired here. The endpoint count in the output helps to tell the cases apart.
- Service keys are exported to `%ProgramData%\IntuneRemediations\Backup` before a start type change.
