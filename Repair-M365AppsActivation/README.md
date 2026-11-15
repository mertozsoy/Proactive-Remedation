# Repair M365 Apps Activation

Microsoft 365 Apps shows **Unlicensed product** or **Product activation failed** when the per-user license files are missing, empty or too old. These scripts check the license store of the signed-in user, move broken files to a backup folder and let Office request a new license.

## Files

| File | Purpose |
|---|---|
| `Detect-M365AppsActivation.ps1` | Reads the Click-to-Run inventory, skips volume licensed and shared computer activation installs, then checks the license files under `%LOCALAPPDATA%\Microsoft\Office\Licenses`. |
| `Remediate-M365AppsActivation.ps1` | Moves the license files to `%LOCALAPPDATA%\IntuneRemediations\Backup\OfficeActivation` and verifies that no broken file remains. Optional identity reset. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Upload `Detect-M365AppsActivation.ps1` and `Remediate-M365AppsActivation.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **Yes**.
4. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot user group. Schedule daily, or run on demand for a device with an activation warning.

## Notes

- Subscription installs are handled. Volume licensed Office and shared computer activation are skipped, because both use a different license store.
- A license file counts as broken when it is zero bytes, and as stale after 45 days. Change `$TokenMaxAgeDays` in both scripts.
- Moved files are kept under `%LOCALAPPDATA%\IntuneRemediations\Backup\OfficeActivation`. Nothing is deleted.
- After a reset the user opens an Office app once so a new license file is written. The script reports `Fixed` when the store is clean.
- `$ResetIdentityCache` also resets the cached Office identity. It is off by default and exports the key before removal.
