# Repair Edge Profile Selection

Checks which Microsoft Edge profile the signed-in user gets on launch and which profile the pinned, Start menu and desktop shortcuts target. The remediation script rewrites the profile argument on user shortcuts so Edge opens the expected profile instead of the profile picker or another profile.

## Files

| File | Purpose |
|---|---|
| Detect-EdgeProfileSelection.ps1 | Reads the Edge profile list from Local State and reports shortcuts or a user policy that point to another profile. |
| Remediate-EdgeProfileSelection.ps1 | Backs up and rewrites the profile argument on user shortcuts and optionally writes the per-user default profile policy. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations > Create**.
2. Upload the detection and remediation scripts.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Set ExpectedProfileDirectory in both scripts to the Edge profile folder name. The value is case sensitive. Confirm it from the Local State file or from edge://version on a reference device.
5. Assign to a pilot group first. A daily schedule is enough for a stable profile layout.

## Notes

- Only .lnk files in the user profile are changed. Each changed shortcut is copied to %LOCALAPPDATA%\IntuneRemediations\Backup\EdgeProfile first.
- The per-user EdgeDefaultProfileEnabled write is opt-in through SetDefaultProfilePolicy. A machine policy value is reported as Blocked and never overwritten.
- Only shortcuts that target msedge.exe or msedge_proxy.exe are touched. Other pinned items are ignored.
- The pinned taskbar button can keep cached arguments until Explorer refreshes or the user re-pins the shortcut.
- The expected profile folder must already exist in Edge. The script does not create or delete Edge profiles.
