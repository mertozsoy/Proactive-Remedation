# Repair Broken Inbox Apps

Intune Remediations script pair. On some devices Photos, Snipping Tool, Calculator or Notepad stay installed but do not open. Repair and Reset in Settings do not help because the user registration or the package files are damaged. This pair finds those apps and registers them again from the package manifest.

## Files

| File | Purpose |
|---|---|
| `Detect-BrokenInboxApps.ps1` | Checks the package status and the package files of each app for the signed-in user. Exits 1 when an installed app is unhealthy. |
| `Remediate-BrokenInboxApps.ps1` | Re-registers the broken apps, falls back to registration by family name and verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-BrokenInboxApps.ps1` as the detection script and `Remediate-BrokenInboxApps.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Runs in the user context. No admin rights are needed to register a package for the current user.
- Apps that are not registered at all are reported as `NotRegistered` and left alone. Those need an app deployment, not a repair.
- `$ResetAppData` is `$false` by default. When set to `$true` the script also calls `Reset-AppxPackage`, which clears the app settings and local app data for that user.
- The repair uses `Add-AppxPackage -Register -DisableDevelopmentMode` on the package manifest. When that fails, the script falls back to `-RegisterByFamilyName`.
- If the staged package is damaged too, the app stays in the failed list and needs a reinstall from the Store or Intune.
