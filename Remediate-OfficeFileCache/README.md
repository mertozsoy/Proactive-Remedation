# Remediate Office File Cache

The Office document cache can grow to tens of gigabytes on a user device and fill the system drive. OfficeFileCache sits inside the user profile and is rarely checked during a disk cleanup. This pair measures the cache of the signed-in user and clears it when it reaches the threshold.

## Files

| File | Purpose |
|---|---|
| `Detect-OfficeFileCache.ps1` | Measures every `OfficeFileCache` folder under `%LOCALAPPDATA%\Microsoft\Office\<version>` and reports whether Office is running. |
| `Remediate-OfficeFileCache.ps1` | Clears the cache contents when the size threshold is reached, then verifies the remaining size. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-OfficeFileCache.ps1` as the detection script and `Remediate-OfficeFileCache.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Assign to a pilot group. Run daily or on demand.
5. Check Device status after the first run and widen the scope.

## Notes

- `$MinimumCacheMB` defaults to 2048 in both scripts. Keep the values identical.
- `$ClearCache = $false` by default: the pair only reports. The cache can hold uploads that have not reached SharePoint or OneDrive yet, even with Office closed. Confirm that no uploads are pending, then enable it.
- `$SkipWhenOfficeRunning = $true` defers the cleanup while Word, Excel, PowerPoint or the Upload Center is open. Pending uploads can be lost if the cache is cleared before they finish.
- The path is discovered under `%LOCALAPPDATA%\Microsoft\Office\<version>\OfficeFileCache`. Both `15.0` and `16.0` folders are measured. Microsoft documents the cleanup through Upload Center and the script removes the same cache contents.
- The script runs as the signed-in user. Other profiles on the device are not touched.
