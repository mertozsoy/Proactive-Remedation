# Remove Stale User Profiles

Intune Remediations script pair. Shared PCs and reassigned laptops collect gigabytes of profiles nobody uses anymore. This pair finds and removes them.

## Files

| File | Purpose |
|---|---|
| `Detect-StaleUserProfiles.ps1` | Finds unloaded AD, local and Entra profiles not used for `$InactiveDays` (90). `$ExcludeRegex` protects admin, service and kiosk accounts. |
| `Remediate-StaleUserProfiles.ps1` | Deletes profiles through Win32_UserProfile, which removes the folder and the ProfileList entry. By default `$Enforce = $false` and the script only reports what it would delete. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-StaleUserProfiles.ps1` as the detection script and `Remediate-StaleUserProfiles.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Weekly.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Keep `$InactiveDays` and `$ExcludeRegex` the same in both scripts.
- Make sure OneDrive Known Folder Move is in place before turning on `$Enforce`.
