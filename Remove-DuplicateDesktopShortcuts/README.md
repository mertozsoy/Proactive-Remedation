# Remove Duplicate Desktop Shortcuts

Intune Remediations script pair. Copy shortcuts such as `Microsoft Edge - Copy`, `Teams (2)` or `Chrome - Kopya` pile up on user desktops after reinstalls and OneDrive desktop sync. This pair finds a copy only when the original shortcut is still in the same folder and moves the copy to a backup folder.

## Files

| File | Purpose |
|---|---|
| `Detect-DuplicateDesktopShortcuts.ps1` | Runs as the user. Reads the `.lnk` and `.url` files on the desktop and flags a file when dropping a copy marker (`- Copy`, `- Kopya`, `- Kopie`, `- Copie`, `- Copia`) or a `(2)` to `(99)` suffix leaves the name of a shortcut that exists in the same folder. |
| `Remediate-DuplicateDesktopShortcuts.ps1` | Moves each flagged copy to `%LOCALAPPDATA%\IntuneRemediations\Backup\DesktopShortcuts\<timestamp>` and scans the desktop again. Nothing is deleted permanently. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-DuplicateDesktopShortcuts.ps1` as the detection script and `Remediate-DuplicateDesktopShortcuts.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- A file is only treated as a duplicate when the original name exists in the same folder. A shortcut like `Teams (2)` without `Teams` is left alone.
- The copy is moved, not deleted. Old timestamp folders under the backup path can be removed later.
- Only the desktop of the signed-in user is scanned. Other profiles on a shared device are not touched.
- Brackets that are not a plain number, for example `App (x64)`, do not match the suffix rule.
- Must run with the logged-on credentials. SYSTEM context would inspect the wrong desktop.
