# Enable UAC

Intune Remediations script pair. Some devices have User Account Control switched off locally, so every process started by an administrator runs elevated without a prompt. This pair reads the EnableLUA value under the UAC policy key and turns it back on.

## Files

| File | Purpose |
|---|---|
| `Detect-EnableUAC.ps1` | Reads `EnableLUA` under `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System`. Exits 1 when the value is 0. |
| `Remediate-EnableUAC.ps1` | Exports the key to `%ProgramData%\IntuneRemediations\Backup`, sets `EnableLUA` to 1 and verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-EnableUAC.ps1` as the detection script and `Remediate-EnableUAC.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- A restart is required before the change takes effect. The script never restarts the device.
- `ConsentPromptBehaviorAdmin` and the other UAC values are reported but left alone, because a baseline may set them on purpose.
- If a domain GPO manages the same setting, it will write the value back on the next policy refresh. Fix the GPO in that case.
- Set `$EnableRemediation = $false` to only report the value.
- Small number of devices per wave. Users see a UAC prompt again after the restart.
