# Report USB Storage Mounted

Detection only script for Intune Remediations. A device control policy is only useful when it holds on the device. Exceptions, a USBSTOR service that another tool turned back on, or a policy that never arrived leave USB storage usable while the console says it is blocked. This script checks the block signals and lists any USB disk that is still present or mounted.

## Files

| File | Purpose |
|---|---|
| `Detect-UsbStorageMounted.ps1` | Reads `Deny_All`, the per-class deny values and the `USBSTOR` service start type. Lists USB disk drives from `Win32_DiskDrive` with their volumes and drive letters. Exits 1 when USB storage is present while a block is configured. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-UsbStorageMounted.ps1` as the detection script. Leave the remediation script empty.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Report only. No device is ejected, disabled or removed.
- `Block` shows the signal that was found: `DenyAll`, `Class`, `UsbStorDisabled` or `None`. With `None` the script exits 0 and prints the inventory only.
- A device that is present but has no drive letter still counts as a finding. It means the block did not stop enumeration.
- Model names and drive letters are printed. No user name and no serial number is collected.
- Set `$IncludeVolumeLetters = $false` to keep drive letters out of the output.
