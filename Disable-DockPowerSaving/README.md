# Disable Dock Power Saving

Docked laptops lose their Ethernet and USB devices after waking from sleep. Windows turns off the PCI Express link and idle USB ports to save power and some dock firmware does not recover cleanly. These scripts check the two settings in the active power scheme and switch both off.

## Files

| File | Purpose |
|---|---|
| `Detect-DockPowerSaving.ps1` | Reads PCI Express link state power management and USB selective suspend from the active power scheme. Exits 1 unless both are set to Off. |
| `Remediate-DockPowerSaving.ps1` | Sets both values to Off with powercfg, reloads the active scheme and reads the values back. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-DockPowerSaving.ps1` and `Remediate-DockPowerSaving.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Assign to a pilot group of docked laptops. Schedule daily.
5. Test a sleep and wake cycle on one device before widening the assignment.

## Notes

- Only the active power scheme is changed. Other saved schemes keep their values, and battery values stay as they are unless `$CheckOnBattery` is set to `$true`.
- Power saving is a trade off. Turning these settings off costs battery life on the devices in scope.
- A centrally deployed power policy can write the values back. Repeated Drift on the same devices means the policy is the owner.
- Network adapter power management is not touched. Microsoft guidance is to leave NDIS power settings to the driver and firmware.
- No restart. `powercfg /setactive` applies the changed scheme immediately.
