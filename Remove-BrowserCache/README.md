# Remove Browser Cache

Edge and Chrome disk caches can consume several gigabytes across shared device profiles. These scripts detect oversized caches in unloaded local profiles and remove cache files after explicit approval.

## Files

| File | Purpose |
|---|---|
| `Detect-BrowserCache.ps1` | Finds Cache directories of at least 256 MB in eligible Edge and Chrome profiles. |
| `Remediate-BrowserCache.ps1` | Deletes files inside eligible Cache directories when enabled and verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload the detection and remediation scripts.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Keep `$MinimumCacheMB` identical in both scripts. Set `$RemoveCacheFiles = $true` only after reviewing the pilot results.
5. Assign to shared or low-disk devices. Schedule daily during an idle maintenance window.

## Notes

- Deletion is disabled by default. ReportOnly exits 1 until cleanup is approved.
- Only normal unloaded profiles directly under the system drive's Users directory are eligible; Healthy covers this scope only.
- Only stable Edge/Chrome Default and Profile-number Cache directories are covered; custom locations and other caches are excluded.
- Browser activity on any session defers deletion. Reparse points are not followed; unreadable caches fail the scan.
- Cookies, history, passwords and downloads are untouched. Cache files are not backed up and are downloaded again as needed.
