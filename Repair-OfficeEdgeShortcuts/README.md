# Repair Office and Edge Shortcuts

Office and Edge shortcut files in the Start menu can lose their target after an update or a profile move. The shortcut stays in the list with a blank icon and does nothing when clicked. These scripts check every profile on the device, repair broken shortcuts in place and recreate missing ones in the all users Start menu.

## Files

| File | Purpose |
|---|---|
| `Detect-OfficeEdgeShortcuts.ps1` | Resolves the Office and Edge executables and checks every Start menu shortcut that points to them. Reports Missing, Broken, Duplicate or Partial per app. |
| `Remediate-OfficeEdgeShortcuts.ps1` | Backs up and repairs broken shortcuts in place and creates missing shortcuts in the all users Start menu. Re-scans before it exits. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-OfficeEdgeShortcuts.ps1` and `Remediate-OfficeEdgeShortcuts.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily, or run on demand for a reported incident.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- The check matches the target executable, so localized Start menu names are not a problem.
- Broken shortcuts are copied to `%ProgramData%\IntuneRemediations\Backup\Shortcuts` before they are rewritten.
- A Start or taskbar layout policy that removes these shortcuts is not overridden. The app stays missing until the policy changes.
- The icon may refresh only after a sign-out. The script does not restart Explorer or sign users out.
- Set `$CreateMissingShortcuts` or `$RepairBrokenShortcuts` to `$false` for a report only run.
