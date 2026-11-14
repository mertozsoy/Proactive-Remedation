# Enable App Installer

Intune Remediations script pair. A CIS hardening baseline that sets **Enable App Installer** to Disabled blocks Intune Store (new) app installs and they fail with 0x87D300CA. This pair finds that policy value and removes it so App Installer returns to Not configured.

## Files

| File | Purpose |
|---|---|
| `Detect-AppInstaller.ps1` | Reads `EnableAppInstaller` under `HKLM\SOFTWARE\Policies\Microsoft\Windows\AppInstaller` and the installed Desktop App Installer package version. Exits 1 when the value is 0. |
| `Remediate-AppInstaller.ps1` | Exports the policy key to a `.reg` backup, removes `EnableAppInstaller` (or sets it to 1 when `$RemovePolicyValue` is `$false`), then re-reads the value. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-AppInstaller.ps1` as the detection script and `Remediate-AppInstaller.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- If the disabled value comes from a configuration profile or GPO, it returns at the next policy refresh. Set that baseline item to Not configured or Enabled as well.
- `$RemovePolicyValue` defaults to `$true`, which returns the setting to Not configured. Set it to `$false` to write 1 instead. Set `$EnableRemediation` to `$false` to report only.
- The script does not install or re-register anything. Check the Store app install status after the next Intune check-in.
- The policy applies to Windows 11 22H2 and later. Other App Installer sub-policies such as the ms-appinstaller protocol are not touched.
- The backup file stays under `%ProgramData%\IntuneRemediations\Backup` and can be imported with `reg import` if the value has to come back.
