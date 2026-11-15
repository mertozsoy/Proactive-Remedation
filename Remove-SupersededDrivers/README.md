# Remove Superseded Drivers

Windows keeps every version of a third-party driver in the driver store. When a newer version is installed the older one stays behind, so the store grows over the years on small disks. This script pair finds driver packages that have a newer package of the same driver family and removes the older ones.

## Files

| File | Purpose |
|---|---|
| `Detect-SupersededDrivers.ps1` | Reads third-party drivers with `Get-WindowsDriver`, groups them by original INF name, provider, class and architecture, and lists packages that are older than the newest package in the group. Packages in use, boot-critical packages and the Printer, System and SCSIAdapter classes are skipped. |
| `Remediate-SupersededDrivers.ps1` | Rebuilds the same list, deletes each package with `pnputil /delete-driver`, then rescans the store and reports what is left. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Upload `Detect-SupersededDrivers.ps1` as the detection script and `Remediate-SupersededDrivers.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Weekly. Start with a pilot group and check the reported package count before you widen the assignment.
5. Keep `$MinimumAgeDays` and `$SkipClasses` identical in both scripts.

## Notes

- The newest package of each driver family is always kept. A package that a device is using is never deleted.
- No `/force` and no `/uninstall`. A package in use stays in the store and is counted as Failed.
- `$MinimumAgeDays = 30` skips packages whose INF date is newer than 30 days.
- `$MaxRemovalsPerRun = 20` bounds each run. Remaining packages are removed on the next run.
- The size in the output is the total FileRepository size, not the exact bytes freed.
