# Disable SMBv1 Client and Server

SMBv1 stays enabled on many workstations after an image or an old GPO. Audit and security scans flag these devices because the client driver and the file sharing server still accept SMBv1. This pair turns off the SMBv1 client, removes the driver from the LanmanWorkstation dependency list and disables the SMBv1 server.

## Files

| File | Purpose |
|---|---|
| `Detect-SMBv1.ps1` | Reads the mrxsmb10 start type, the LanmanWorkstation dependency list and the SMBv1 server state. Reports the SMB1Protocol feature state. Exits 1 on drift. |
| `Remediate-SMBv1.ps1` | Exports the three service keys, sets mrxsmb10 to disabled, removes MRxSMB10 from the LanmanWorkstation dependencies and turns off the SMBv1 server. Verifies both sides. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-SMBv1.ps1` as the detection script and `Remediate-SMBv1.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, then widen the scope.

## Notes

- The client change takes effect after the next restart. The script never restarts the device.
- A device that still needs SMBv1 for an old NAS or a legacy application loses access to that share after the restart.
- `$RemoveSmb1Feature = $false` by default. Set it to `$true` to remove the SMB1Protocol optional feature as well. That step also needs a restart.
- `$EnableRemediation = $false` makes the pair report only.
- Backups of the changed keys go to `%ProgramData%\IntuneRemediations\Backup\SMBv1`.
