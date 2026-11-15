# Disable Device CoInstallers

Checks whether device co-installers are disabled. With explicit approval, remediation sets DisableCoInstallers to DWORD 1 and verifies the registry setting. Existing vendor applications are not removed.

## Files

| File | Purpose |
|---|---|
| `Detect-DeviceCoInstallers.ps1` | Detects a missing value, incorrect type or value other than 1. |
| `Remediate-DeviceCoInstallers.ps1` | Reports by default; when enabled, exports the existing key, applies DWORD 1 and reads it back. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload the detection and remediation scripts from the Files table.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Enforce script signature check: **No**, unless signed with a trusted certificate.
5. Assign to a pilot group and schedule daily. Enable remediation only after reviewing the Notes.

## Notes

- Microsoft Learn does not document this disable value; the SySS advisory documents it. `$EnableRemediation = $false` keeps changes off pending approval.
- Check ownership before enabling changes. Exclude devices managed by GPO or Intune for this setting; `$ManagedExternally = $true` blocks writes. Ownership is not auto-detected.
- Legacy peripheral setup may need co-installers. Test new device installation; registry verification alone does not prove blocking.
- Existing keys are exported to `%ProgramData%\IntuneRemediations\Backup`. Roll back only the changed value using the saved state; remove it if originally absent.
- No driver or application is uninstalled. No restart is triggered; this is not a replacement for vendor security updates.
