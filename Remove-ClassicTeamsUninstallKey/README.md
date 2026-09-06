# Remove Classic Teams Uninstall Registry Key

Intune Proactive Remediation script pair that cleans up the stale `...\CurrentVersion\Uninstall\Teams` registry key left behind by the retired **classic Microsoft Teams** client, across every user profile on a device (including profiles that aren't currently logged in).

## Files

| File | Purpose |
|---|---|
| `Detect-ClassicTeamsUninstallKey.ps1` | Enumerates all non-special user profiles. For each, checks the loaded `HKEY_USERS` hive directly if the user is logged in, or loads the profile's offline `NTUSER.DAT` hive temporarily if not, and checks for the `Uninstall\Teams` key. Exits `1` if found in any profile, `0` if clean. Logs to `C:\Temp\IntunePR-Teams-UninstallKey-Detection.log`. |
| `Remediate-ClassicTeamsUninstallKey.ps1` | Same profile-enumeration approach, but removes the key wherever found (loaded or offline hive), then re-verifies across all profiles. Exits `1` if any instance remains, `0` if fully clean. Logs to `C:\Temp\IntunePR-Teams-UninstallKey-Remediation.log`. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context** (required to enumerate `Win32_UserProfile`, load/unload offline NTUSER.DAT hives via `reg.exe`, and access `HKEY_USERS`).
4. Assign to devices that previously had classic Teams installed.

## Notes

- No environment-specific values are present in these scripts.
- Offline hives are loaded under a temporary, per-run unique key name and always unloaded in a `finally` block to avoid leaving hives mounted.
