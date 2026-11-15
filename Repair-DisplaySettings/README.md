# Repair Display Settings

After the August 2025 cumulative update (KB5063878) Settings > System > Display stays on a loading circle on some devices. Reinstalling the Settings app does not help. The cause is the Connected Devices Platform services. Their start type is Disabled and the Display page waits for them. This pair reads the start types and sets them back to Automatic.

## Files

| File | Purpose |
|---|---|
| `Detect-DisplaySettings.ps1` | Reads the `Start` value of `CDPSvc`, the `CDPUserSvc` template and every `CDPUserSvc_*` per-user instance. Also reads the `EnableCdp` policy. Exits 1 when a start type is not Automatic or the policy blocks the platform. |
| `Remediate-DisplaySettings.ps1` | Exports the service keys to `%ProgramData%\IntuneRemediations\Backup`, sets the start type to Automatic and starts `CDPSvc` when it is stopped. Verifies the values and exits 0 only when no drift is left. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-DisplaySettings.ps1` as the detection script and `Remediate-DisplaySettings.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- A sign-out or a restart is needed after the change. The script never restarts the device.
- `$ClearCdpPolicy = $false` leaves the `EnableCdp` policy in place. The policy is reported as `Policy=Disallowed` so you can decide on the baseline.
- The per-user instances are recreated at the next sign-in from the template. The script also fixes the ones that exist at run time.
- Devices that installed the September 2025 update already have working Display settings. The script reports `Healthy` on them.
