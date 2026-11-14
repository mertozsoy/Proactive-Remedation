# Report Hardware Inventory

Detection only script for Intune Remediations. The Intune hardware inventory does not show BIOS date, battery wear or some firmware details. This script collects them in one line.

## Files

| File | Purpose |
|---|---|
| `Detect-HardwareInventory.ps1` | Writes one JSON line with make, model, serial, BIOS version and date, TPM, Secure Boot, CPU, RAM, OS build, system disk, battery wear and last boot. Always exits `0`. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-HardwareInventory.ps1` as the detection script. Leave the remediation script empty.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Weekly.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Export the device status report and parse the output column as JSON.
