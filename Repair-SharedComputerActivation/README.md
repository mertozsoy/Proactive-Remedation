# Repair Shared Computer Activation

On shared computers, Office shows **Unlicensed product** or asks the user to sign in again at every session when the per-user licensing token is missing, empty or too old. These scripts check the licensing token cache of the signed-in user and reset unusable tokens so Office can request a new one.

## Files

| File | Purpose |
|---|---|
| `Detect-SharedComputerActivation.ps1` | Reads the shared computer licensing switch and inspects the licensing token folder of the signed-in user. |
| `Remediate-SharedComputerActivation.ps1` | Recreates a missing token folder, moves unusable tokens to a backup folder and verifies the cache. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Upload `Detect-SharedComputerActivation.ps1` and `Remediate-SharedComputerActivation.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **Yes**.
4. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot user group on shared devices. Schedule daily, or run on demand for a confirmed Unlicensed product case.

## Notes

- Devices without the Click-to-Run shared computer licensing switch set to 1 are skipped. The scripts never change that machine value.
- A token file counts as unusable when it is zero bytes or older than 25 days. Change `$TokenMaxAgeDays` in both scripts if your tenant renews differently.
- Moved tokens are kept under `%LOCALAPPDATA%\IntuneRemediations\Backup\OfficeLicensing`. Nothing is deleted permanently and no user document is touched.
- After a reset the user must open an Office app once so a new token is issued. The script reports `Pending` until a token exists again.
- A roaming token folder from `SCLCacheOverride` is used when configured. A missing network path is reported, not created. Office apps are not closed or restarted.
