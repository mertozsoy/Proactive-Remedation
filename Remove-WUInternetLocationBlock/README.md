# Remove WU Internet Location Block

Intune Remediations script pair. An old WSUS GPO often leaves `DoNotConnectToWindowsUpdateInternetLocations` behind. With that value set the device cannot reach the public update endpoints, so Microsoft Store (new) apps and Company Portal fail to install. This pair removes the value on devices that no longer use WSUS.

## Files

| File | Purpose |
|---|---|
| `Detect-WUInternetLocationBlock.ps1` | Reads `DoNotConnectToWindowsUpdateInternetLocations` and `DisableWindowsUpdateAccess` under `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate`. Flags the device when a value is 1 and no WSUS server is in use. |
| `Remediate-WUInternetLocationBlock.ps1` | Removes the blocking values, restarts `wuauserv` and `InstallService` if they are running and reads the key again to verify. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-WUInternetLocationBlock.ps1` as the detection script and `Remediate-WUInternetLocationBlock.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Devices that still scan against WSUS (`UseWUServer=1` with a `WUServer` address) are reported as `WsusInUse` and left alone. Set `$RemoveWhenWsusConfigured = $true` only when you are sure the WSUS policy is a leftover.
- If the same value exists under `PolicyManager\current\device\Update`, the device is reported as `PolicyManaged` and nothing is changed.
- If a domain GPO still applies the setting, it comes back on the next Group Policy refresh. Remove the GPO first.
- Both value names come from Microsoft's Windows Autopatch conflicting configurations article.
- The script does not trigger Store installs. Intune retries them on its own.
