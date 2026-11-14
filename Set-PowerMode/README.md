# Set Power Mode

Windows 11 24H2 energy recommendations can leave Intel laptops on Best power efficiency. The device then feels slow even when it is plugged in. This script pair reads the user configured AC and DC power mode through the PowrProf API and sets a replacement mode when either one is Best power efficiency.

## Files

| File | Purpose |
|---|---|
| `Detect-PowerMode.ps1` | Checks the Windows build, the Energy Saver policy and the AC and DC power mode. |
| `Remediate-PowerMode.ps1` | Writes the replacement power mode for AC and DC when needed and verifies the new value. |

## Deployment (Intune)

1. Set `$ReplacementPowerMode` identically in both scripts. The starting value is Balanced.
2. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
3. Upload the detection and remediation scripts.
4. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot group of affected laptops and schedule daily. Compare responsiveness and battery life before widening the scope.

## Notes

- Windows 11 only. Windows 10 devices return NotApplicable.
- Only Best power efficiency is replaced. A device that is already on Best performance is left alone.
- An Energy Saver always-on policy is reported as PolicyManaged. Change that policy instead of the power mode.
- The script sets the user configured mode. Windows can still override the effective mode with other signals such as battery saver.
- Previous AC and DC values are logged. To roll back, remove the assignment and select the old mode in Settings.
