# Disable Startup Sound

Intune Remediations script pair. Windows plays a startup sound on every boot. The Sound settings switch for it is per device, but Settings Catalog has no matching setting and an Entra joined fleet usually has no GPO to set it. This pair reads the startup sound values and turns the sound off with the policy value.

## Files

| File | Purpose |
|---|---|
| `Detect-StartupSound.ps1` | Reads `DisableStartupSound` under `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System` and under `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation`. Exits 1 when the policy value is not 1. |
| `Remediate-StartupSound.ps1` | Exports the `Policies\System` key to `%ProgramData%\IntuneRemediations\Backup`, writes `DisableStartupSound` as DWORD 1, then reads the value back. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-StartupSound.ps1` as the detection script and `Remediate-StartupSound.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- The new value applies at the next boot. The script never restarts the device.
- The policy value covers every user on the device and greys out the toggle in Sound settings.
- When the policy value is 0, a GPO forces the sound on. The script reports `Skipped` and does not overwrite it.
- Set `$EnableRemediation` to `$false` to report without writing the value.
- Windows Server devices return `NotApplicable`.
