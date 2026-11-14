# Report Disk Health

Detection only script for Intune Remediations. Disks usually give warnings long before they fail. This script reads them so you can replace the disk before the user loses data.

## Files

| File | Purpose |
|---|---|
| `Detect-DiskHealth.ps1` | Checks HealthStatus, OperationalStatus, SSD wear (`$WearThreshold` 85), uncorrected read and write errors and temperature (`$MaxTemperatureC` 70). USB disks are skipped. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-DiskHealth.ps1` as the detection script. Leave the remediation script empty.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Weekly.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Detection only. Export the report to plan replacements.
