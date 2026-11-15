# Set Default Printer

Windows default printer management makes the last used queue the default, and a spooler restart or a removed queue can leave the user on Microsoft Print to PDF. These scripts compare the signed-in user's default printer with an approved name, turn off default printer management and set the approved printer again.

## Files

| File | Purpose |
|---|---|
| `Detect-DefaultPrinter.ps1` | Compares the default printer and the management value with the approved target. |
| `Remediate-DefaultPrinter.ps1` | Backs up the key, turns off management, sets the approved default printer and verifies both. |

## Deployment (Intune)

1. Set `$ExpectedDefaultPrinter` in both scripts, for example `'\\print01.contoso.local\Floor2'`. Add alternate queue names to `$AcceptedDefaultPrinters` if a user group may use more than one printer.
2. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
3. Select both scripts. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** unless the scripts are signed.
4. Assign to a pilot user group and run once a day. Print from two applications on a test device to confirm that the default printer stays.
5. Exclude meeting room and shared accounts that must keep the last used printer.

## Notes

- `$ExpectedDefaultPrinter` must match the exact name that Get-Printer shows. The name is case insensitive, aliases are not resolved.
- The management value is `LegacyDefaultPrinterMode` = 1 under `HKCU\Software\Microsoft\Windows NT\CurrentVersion\Windows`. Windows writes 0 when "Let Windows manage my default printer" is on.
- Both scripts return NotApplicable when the approved printer is not installed. Deploy the queue first, for example with the required printers script.
- The key is exported to `%LOCALAPPDATA%\IntuneRemediations\Backup` before any write. `$BackupRegistryKey = $false` skips the export.
- If an Intune or Group Policy setting turns default printer management back on, detection returns Drift again. Remove that assignment instead of rerunning the script.
