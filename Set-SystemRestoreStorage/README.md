# Set System Restore Storage

System Protection can be set to use almost the whole volume. Restore points then grow until the disk has little free space and updates fail. These scripts read the maximum shadow copy storage of each protected volume and lower it to a fixed percentage.

## Files

| File | Purpose |
|---|---|
| `Detect-SystemRestoreStorage.ps1` | Reads `Win32_ShadowStorage` and reports the limit of each protected volume as a percentage of the volume size. Exits 1 when a limit is unbounded or above `$MaxAllowedPercent`. |
| `Remediate-SystemRestoreStorage.ps1` | Runs `vssadmin resize shadowstorage` for volumes above the limit, then reads the values back and checks the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-SystemRestoreStorage.ps1` and `Remediate-SystemRestoreStorage.ps1`.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the reported percentages, then widen the scope.

## Notes

- Shrinking shadow storage makes VSS delete the oldest restore points that no longer fit. The scripts never delete restore points directly and never disable System Protection.
- Volumes without a shadow storage association are skipped. When System Protection is off on every volume the result is NotApplicable.
- Keep `$TargetPercent` and `$MaxAllowedPercent` identical in both scripts. The default target is 10 percent of the volume and the allowed maximum is 20 percent.
- No reboot and no service restart. `vssadmin` uses the Volume Shadow Copy service, which starts on demand.
- System Protection scope, schedule and retention are not changed. No policy or registry value is written.
