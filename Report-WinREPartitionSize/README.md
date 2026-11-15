# Report WinRE Partition Size

Detection only script for Intune Remediations. Windows needs 250 MB of free space in the WinRE partition to service the recovery image. When that space is missing the recovery update fails and the device stays behind on every later release. This script finds the WinRE partition, reads its size and free space, and flags the devices that do not meet the requirement.

## Files

| File | Purpose |
|---|---|
| `Detect-WinREPartition.ps1` | Reads the WinRE location from `reagentc /info` and falls back to the GPT recovery partition type. Reports the disk and partition number, total size, free space and the number of recovery partitions. Exits 1 when free space is below 250 MB. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-WinREPartition.ps1` as the detection script. Leave the remediation script empty.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Weekly.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Report only. No partition is resized, mounted or moved.
- `Placement` shows where the image sits: `Dedicated`, `WindowsVolume`, or `RecoveryGptType` when the path from reagentc was not readable.
- `Small` means free space is under 250 MB. Plan the partition resize per model, because the free space comes from the Windows partition.
- `Unknown` means the volume could not be read. The disk and partition numbers are in the output and in the log.
- A device with WinRE disabled and no recovery partition exits 0 as `NotApplicable`.
