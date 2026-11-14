# Disable Dock NIC Power Saving

Dock and USB-C Ethernet adapters ship with power saving turned on. Windows then powers the adapter down on idle or after sleep. The link drops, file copies stall and the device disappears from the network until the next dock cycle. These scripts find those adapters, turn power saving off and set Energy Efficient Ethernet keywords to 0.

## Files

| File | Purpose |
|---|---|
| `Detect-DockNicPowerSaving.ps1` | Lists physical Ethernet adapters on the USB bus or with a dock description. Reads `AllowComputerToTurnOffDevice` and the EEE keywords. Exits 1 when power saving is on. |
| `Remediate-DockNicPowerSaving.ps1` | Runs `Disable-NetAdapterPowerManagement` and sets matching EEE keywords to 0 without restarting the adapter, then re-checks every adapter. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-DockNicPowerSaving.ps1` as detection and `Remediate-DockNicPowerSaving.ps1` as remediation.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
4. Schedule: Once for the fleet, daily for devices that move between docks.
5. Assign to a pilot group of dock users first, then widen the scope.

## Notes

- `$AdapterScope = 'DockAndUsb'` limits the change to USB and dock Ethernet adapters. Set it to `All` to include built-in NICs.
- Wake on LAN stops working on the adapter because the whole power management block is disabled. Wake from keyboard or power button is not affected.
- `-NoRestart` keeps the link up during the change. The EEE value takes effect after the next adapter reset or reboot.
- `$DisableEnergyEfficientEthernet = $true` only touches keywords the driver actually exposes. Missing keywords are skipped.
- Logs: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT_DockNicPowerSaving.log`.
