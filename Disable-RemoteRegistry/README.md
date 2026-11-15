# Disable Remote Registry

Remote Registry lets a remote user read and change the registry of the device. Windows clients ship with the service disabled, but old images, legacy tools and manual fixes turn it back on. This pair finds clients where the RemoteRegistry service is not disabled and sets the start type to Disabled.

## Files

| File | Purpose |
|---|---|
| `Detect-RemoteRegistry.ps1` | Reads the `Start` value of the RemoteRegistry service key and the service state. Exits 1 when the service is not disabled or is running. Servers are skipped. |
| `Remediate-RemoteRegistry.ps1` | Stops the service when it is running, sets the start type to Disabled with `Set-Service` and verifies both values. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-RemoteRegistry.ps1` as the detection script and `Remediate-RemoteRegistry.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- The service is stopped before the start type changes. No restart is needed.
- A registry backup of the service key goes to `%ProgramData%\IntuneRemediations\Backup\RemoteRegistry`.
- If a domain GPO sets the service under Security Settings > System Services, the policy wins at the next refresh. Move the setting to Intune or remove the GPO entry.
- Exclude devices that still need Remote Registry for an inventory or monitoring tool.
- `$EnableRemediation = $false` turns the script into a report-only check.
