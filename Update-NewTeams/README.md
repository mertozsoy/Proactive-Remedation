# Update New Teams

New Teams can remain below the version required by your security team. This script pair inventories MSTeams across users and can run Microsoft's Teams bootstrapper to replace an outdated installation, then checks the versions again.

## Files

| File | Purpose |
|---|---|
| `Detect-NewTeams.ps1` | Lists version bounds without user identifiers. Flags any returned version below `$MinimumVersion`. |
| `Remediate-NewTeams.ps1` | Defaults to report mode. When enabled, checks an approved local bootstrapper's SHA256, runs `-p`, then verifies the minimum version. |

## Deployment (Intune)

1. Set `$MinimumVersion` identically in both scripts to the four-part MSIX version approved for your deployment ring. Obtain the threshold from your current Defender recommendation and validate it against Teams MSIX inventory; no security baseline is hardcoded.
2. Go to **Devices > Scripts and remediations > Remediations > Create**. Upload the detection and remediation files.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for these unsigned files, or sign them under your signing policy.
4. Assign to a pilot device group. Schedule daily, preferably outside Teams usage hours.
5. To enable updates after review, deploy the latest Microsoft `teamsbootstrapper.exe` separately to a local folder writable only by administrators and SYSTEM. Verify its Microsoft signature during staging. Set `$BootstrapperPath` to its absolute path and `$BootstrapperSha256` to that approved file's SHA256. Then set `$EnableRemediation = $true`. Refresh the file and pin together whenever the bootstrapper changes.

## Notes

- Report only by default. Set `$MinimumVersion`, `$BootstrapperPath` and `$EnableRemediation = $true` after the pilot. The bootstrapper file is pinned by SHA256.
- The update runs `teamsbootstrapper.exe -p`, which installs the latest Teams build. It does not pin an exact Teams version.
- If Teams or the bootstrapper is running the device is deferred to the next run. Nothing is closed by force and the device is not restarted.
- Old staged registrations can keep a device in drift after the update. Check the AppX deployment events on those devices.
- Exclude VDI, Teams Rooms and devices that keep Teams on a fixed version on purpose.
