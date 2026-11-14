# Remediate OneDrive Disk Space

Intune Remediations script pair. On devices with a small SSD, OneDrive keeps files downloaded locally and free space runs out, which blocks Windows updates and new installs. This pair measures the free space and how much OneDrive holds locally, then converts files to online-only with the Files On-Demand attribute when the disk is low.

## Files

| File | Purpose |
|---|---|
| `Detect-OneDriveDiskSpace.ps1` | Runs as the user. Reads free space on the system drive. If it is below `$MinFreeSpaceGB`, checks that Files On-Demand is available and counts the locally available OneDrive data with the file attribute bits. Exits 1 only when unpinning can return at least `$MinReclaimGB`. |
| `Remediate-OneDriveDiskSpace.ps1` | Unpins the largest locally available files with `attrib +U -P` until the target free space is reached. Verifies each file and the free space. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-OneDriveDiskSpace.ps1` as the detection script and `Remediate-OneDriveDiskSpace.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Files with the pinned attribute, meaning Always keep on this device, are skipped. Set `$IncludePinned = $true` only if you want those files converted too.
- No file is deleted. Content stays in OneDrive and downloads again when the user opens the file.
- If the Files On-Demand driver is not running or a policy turns the feature off, the scripts report the state and change nothing.
- Thresholds are `$MinFreeSpaceGB` and `$TargetFreeSpaceGB` in both scripts. Keep them in step.
- OneDrive dehydrates in the background, so the free space figure in the output can lag a few minutes behind the run.
