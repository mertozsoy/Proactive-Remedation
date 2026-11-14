# Remove Public Desktop Shortcuts

Intune Remediations script pair. Installers drop shortcuts on the Public Desktop and standard users cannot delete them without admin rights. This pair removes the shortcuts you list and keeps them away after application updates put them back.

## Files

| File | Purpose |
|---|---|
| `Detect-PublicDesktopShortcuts.ps1` | Lists `.lnk` and `.url` files on the Public Desktop and matches their names (without extension) against `$ShortcutNames`. Wildcards are supported. |
| `Remediate-PublicDesktopShortcuts.ps1` | Clears the read-only attribute and deletes the matching files. Checks the folder again afterwards. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-PublicDesktopShortcuts.ps1` as the detection script and `Remediate-PublicDesktopShortcuts.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Edit `$ShortcutNames` in both scripts and keep the lists identical. The default list is an example.
- Only the Public Desktop is touched. Shortcuts on a user's own Desktop are left alone.
- Only `.lnk` and `.url` files are considered. Other files on the Public Desktop are never deleted.
- Use exact names where you can. A pattern such as `*` would remove every shortcut, including the ones you deployed on purpose.
- Applications often recreate their shortcut on update. A daily schedule removes it again.
