# Remove Dell SupportAssist Snapshots

Intune Remediations script pair. Dell SupportAssist OS Recovery keeps system repair snapshots under `ProgramData`, and on small disks they can grow to tens of gigabytes. This pair measures the snapshot folder and, when you turn it on, deletes its content.

## Files

| File | Purpose |
|---|---|
| `Detect-DellSupportAssistSnapshots.ps1` | Measures `%ProgramData%\Dell\SARemediation\SystemRepair\Snapshots` and flags the device when it is larger than `$MaxSizeGB` (5). |
| `Remediate-DellSupportAssistSnapshots.ps1` | With `$Enforce = $true` deletes the items in the snapshot folder and reports the space gained. With the default `$Enforce = $false` it only reports. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-DellSupportAssistSnapshots.ps1` as the detection script and `Remediate-DellSupportAssistSnapshots.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Deleting the snapshots removes the SupportAssist restore points of the device. This cannot be undone, so `$Enforce` is off by default.
- The script does not uninstall SupportAssist and does not change its settings. If the product stays installed, new snapshots will be created. Remove the Dell SupportAssist OS Recovery Plugin or SupportAssist Remediation app with your normal app deployment if you do not use them.
- Devices without the folder return `NotApplicable`, so the pair can be assigned to mixed hardware.
- Items that are locked by the Dell service are counted as `FailedItems` and tried again on the next run.
