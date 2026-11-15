# Remove Software Distribution Backups

Windows Update repairs often rename `SoftwareDistribution` to `SoftwareDistribution.old` and `catroot2` to `catroot2.old`. The old folders are never deleted and can take several GB on small disks. This pair finds those backups and removes them once they are past the age limit.

## Files

| File | Purpose |
|---|---|
| `Detect-SoftwareDistributionBackups.ps1` | Reports `SoftwareDistribution.old` and `catroot2.old` when the live folder exists and the backup is older than `$MinimumAgeDays`. |
| `Remediate-SoftwareDistributionBackups.ps1` | Deletes the stale backup folders, takes ownership only when the delete is denied, then verifies the folders are gone. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-SoftwareDistributionBackups.ps1` as the detection script and `Remediate-SoftwareDistributionBackups.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Weekly.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- A backup is skipped when the live folder is missing, so the only copy is never deleted.
- Cleanup is skipped while TrustedInstaller, TiWorker or Setup is running.
- No service is restarted and the live update folders are not touched.
- `$MinimumAgeDays` defaults to 7. Raise it if updates are installed less often.
- Set `$RemoveBackups = $false` to report the folders without deleting them.
