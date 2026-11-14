# Remove Per User Chrome Zoom

When Chrome or Zoom is installed without admin rights the installer puts a copy under AppData in the user profile. That copy is outside Program Files, so the machine wide deployment and the update tasks do not touch it. It also stays on an old build and shows up as vulnerable software in Defender. This pair finds the per-user copies in every profile and removes them with the uninstall command the app registered for that user.

## Files

| File | Purpose |
|---|---|
| `Detect-PerUserChromeZoom.ps1` | Checks `AppData\Local\Google\Chrome\Application\chrome.exe` and `AppData\Roaming\Zoom\bin\Zoom.exe` in every local user profile. Output lists the app counts; no user names are written. |
| `Remediate-PerUserChromeZoom.ps1` | Opens the registry of each profile, reads the `QuietUninstallString` or `UninstallString` from the app's own uninstall entry and runs it. Skips a profile while the app is running and checks the executable afterwards. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-PerUserChromeZoom.ps1` as the detection script and `Remediate-PerUserChromeZoom.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Medium impact: the app is uninstalled from the user profile. Announce it before the rollout and start on a pilot group.
- No uninstall flags are hardcoded. The script reads the command that the per-user install wrote to its own uninstall key, so the same code works for other versions of the two apps.
- If the app is running in the profile the entry is skipped and reported as `Skipped`. The next daily run picks it up. Closing the app is left to the user.
- Chrome bookmarks, history and Zoom chat data stay in the profile. Only the application folders are removed. Delete the user data by hand if the profile is being cleaned for another reason.
- `NTUSER.DAT` is mounted read-only for profiles that are not signed in. It is unloaded right after the check. Set `$MountSignedOutProfiles` to `$false` to touch signed-in profiles only.
- `$MaxProfilesPerRun` limits how many profiles are handled in one run. A device with many profiles finishes in several days instead of one long run.
- When no uninstall entry exists the result is `NoUninstaller` and the folder is left in place. Deleting an app folder by hand leaves the uninstall entry, the shortcuts and the update tasks behind.
- Report only by default. `$UninstallPerUserApps` is `$false`, so the first rollout only lists the profiles and the output starts with `ReportOnly`. Set it to `$true` after the pilot.
- Chrome gets `--force-uninstall` added so its uninstaller does not wait for a confirmation window. Running a per-user uninstaller from the SYSTEM account was not tested on a device. Check the `Failed` reasons on the pilot group before a wide rollout.
