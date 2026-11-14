# Add Company Shortcuts

Intune Remediations script pair. Users delete the Company Portal or intranet shortcut and later call because they cannot find it. This pair keeps a list of standard shortcuts on the Desktop or Start menu of each user and puts back the ones that are missing.

## Files

| File | Purpose |
|---|---|
| `Detect-CompanyShortcuts.ps1` | Runs as the user. Checks each entry in `$Shortcuts`: web addresses become `.url` files, everything else a `.lnk`. Flags shortcuts that are missing or point to a different target. |
| `Remediate-CompanyShortcuts.ps1` | Creates the missing or changed shortcuts with `WScript.Shell` (`.lnk`) or as a plain `[InternetShortcut]` file (`.url`). Verifies the list again. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-CompanyShortcuts.ps1` as the detection script and `Remediate-CompanyShortcuts.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Edit `$Shortcuts` in both scripts and keep the two lists identical. The entries in the repo are examples (`intranet.contoso.com`).
- `Location` is `Desktop` or `StartMenu`. The Desktop path is resolved through the shell, so it follows OneDrive Known Folder Move.
- `RequiresAppx` skips an entry when that Store app is not installed for the user. A file target that does not exist is skipped the same way.
- `Icon` is optional and must be a local `.ico` or `.exe` path that already exists on the device.
- Must run with the logged-on credentials.
