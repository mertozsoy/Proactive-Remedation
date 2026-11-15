# Remediate Camera Mic Access

Intune Remediations script pair. A user turns off camera or microphone access in the Windows privacy settings and forgets about it. Teams then says no camera was found and the ticket lands on the service desk. This pair reads the per-user consent store and turns access back on for the user, the desktop apps bucket and the configured app keys.

## Files

| File | Purpose |
|---|---|
| `Detect-CameraMicAccess.ps1` | Runs as the user. Reads `HKCU\...\CapabilityAccessManager\ConsentStore` for `webcam` and `microphone`, plus the `NonPackaged` and `$AppKeys` subkeys. Reads the App Privacy policy and the machine level value to tell a user setting apart from a managed block. Exits 1 when a repairable value is `Deny`. |
| `Remediate-CameraMicAccess.ps1` | Exports the consent keys to a backup file, sets the affected values to `Allow` and reads the store again. Leaves policy and device level blocks alone and reports them. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-CameraMicAccess.ps1` as the detection script and `Remediate-CameraMicAccess.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily. Run once per user, not per device.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Only the signed-in user is changed. The script runs in user context and writes to `HKCU`.
- A `Deny` from the App Privacy policy or from the machine level key is reported, never overwritten.
- Default entry in `$AppKeys` is the new Teams client. Add other package family names as needed.
- A running app picks up the new consent after it is restarted. The script does not close apps.
- The previous values are in the log file and in the `.reg` backup under `%LOCALAPPDATA%\IntuneRemediations\Backup`.
