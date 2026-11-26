# Repair Audio Device

After a cumulative update some laptops lose sound. Device Manager shows the audio controller or its endpoint with a problem code and the speaker icon gets a red X. The usual fix is to uninstall the device and scan for hardware changes. This pair finds those devices and does that without a remote session.

## Files

| File | Purpose |
|---|---|
| `Detect-AudioDevice.ps1` | Reads present `MEDIA` and `AudioEndpoint` devices with `Get-PnpDevice` and lists every device whose problem code is not zero. `$IgnoredProblemCodes` holds the codes that are not treated as an error. |
| `Remediate-AudioDevice.ps1` | Removes each device in a problem state with `pnputil /remove-device`, scans the device tree, restarts the audio services and verifies that no audio device keeps an error code. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-AudioDevice.ps1` as the detection script and `Remediate-AudioDevice.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- The device is removed for a few seconds and the sound drops. Run it outside meeting hours on a pilot group first.
- Set `$RemoveDevice = $false` to leave the device in place and only report the problem code.
- If the removal fails the script tries `pnputil /restart-device` and then a disable and enable cycle.
- Windows 10 version 2004 (build 19041) or later is required for `pnputil /remove-device` and `/scan-devices`.
- A device that returns with the same problem code needs a driver package. A rescan alone will not fix it.
