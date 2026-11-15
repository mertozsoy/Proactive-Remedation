# Remove Delivery Optimization Bypass

An old GPO or a debloat script can leave DownloadMode set to 100 (Bypass) or 99 (Simple) under the Delivery Optimization policy key. In both modes the device skips the Delivery Optimization service and Win32 app content downloads slowly, which pushes the ESP close to its timeout. This pair removes the leftover value and restarts the Delivery Optimization service.

## Files

| File | Purpose |
|---|---|
| `Detect-DeliveryOptimizationBypass.ps1` | Reads `DownloadMode` under `HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization` and flags 99 or 100. |
| `Remediate-DeliveryOptimizationBypass.ps1` | Exports the policy key, deletes `DownloadMode`, restarts `DoSvc` and verifies the value is gone. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Upload the detection and remediation scripts.
3. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Assign to a pilot group and schedule daily. Compare Win32 app install times before widening the scope.
5. Remove the source GPO or debloat task first. Otherwise the value returns on the next policy refresh.

## Notes

- A device where `DODownloadMode` exists under `PolicyManager\current\device\DeliveryOptimization` is reported as `MdmManaged` and left alone. Change the Intune policy instead.
- Simple mode (99) is valid for devices without internet access. Set `$TreatSimpleModeAsDrift = $false` if your fleet uses it on purpose.
- The previous value is stored as a `.reg` export under `%ProgramData%\IntuneRemediations\Backup\DeliveryOptimizationBypass`.
- `DoSvc` is restarted only when it exists. Set `$RestartDoService = $false` to skip the restart.
- Only the policy value is removed. The Delivery Optimization cache and the Settings app entries are not touched.
