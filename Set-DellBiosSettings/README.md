# Set Dell BIOS Settings

Reads managed BIOS attributes on Dell devices through the native WMI interface and checks them against a small baseline. The remediation script backs up the current values, writes the baseline and verifies the result.

## Files

| File | Purpose |
|---|---|
| `Detect-DellBiosSettings.ps1` | Reads the managed BIOS attributes and returns 1 when one of them is out of standard. |
| `Remediate-DellBiosSettings.ps1` | Exports the current values, writes the baseline through SetAttribute and re-reads the attributes. |

## Deployment (Intune)

1. Edit the `$DesiredSettings` list in both scripts with the attribute names and values your hardware supports. Keep both lists identical.
2. Fill `$BiosAdminPassword` in the remediation script if the device has a BIOS admin password set.
3. Go to **Devices > Scripts and remediations > Remediations > Create** and add both scripts.
4. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a small Dell pilot group first and review the output after one restart.

## Notes

- `$ManageSecureBoot` is false by default. Secure Boot changes can affect boot, so enable it only after testing on the model.
- If a BIOS admin password is set and `$BiosAdminPassword` is empty the remediation exits 1 with `BiosAdminPasswordRequired` and writes nothing.
- The WMI BIOS classes exist on Dell hardware from 2018 and later. Older models return `NotApplicable`.
- Attributes that are missing or do not accept the configured value are counted as skipped. They do not block a healthy result.
- Current values are saved to `%ProgramData%\IntuneRemediations\Backup`. BIOS changes take effect after a restart, which the script never performs.
