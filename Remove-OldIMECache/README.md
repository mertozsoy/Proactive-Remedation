# Remove Old IMECache

Old Win32 application content can accumulate in Windows IMECache and consume disk space. These scripts detect retained content and remove eligible directories after age and activity checks.

## Files

| File | Purpose |
|---|---|
| `Detect-OldIMECache.ps1` | Reports old GUID_version directories and flags at least 512 MB of eligible content. |
| `Remediate-OldIMECache.ps1` | Rechecks candidates, removes files and empty directories, then verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-OldIMECache.ps1` and `Remediate-OldIMECache.ps1`.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
4. Match the retention and size settings in both scripts. Start with a pilot group.
5. Schedule daily outside application deployment windows. Review deferred and failed results before expanding assignments.

## Notes

- Defaults: 30 days and 512 MB. Every entry must have old creation and modification times; the minimum allowed retention is 7 days.
- Only GUID_version directories under `%SystemRoot%\IMECache` qualify. Loose files, recent trees and reparse points stay untouched; scans fail above 50,000 entries per directory.
- Cleanup is enabled. Set `$EnableCleanup = $false` to defer deletion; installer activity also defers it with exit 1.
- Age and process checks cannot prove content is unused. Use a deployment-free window; cached installers may be needed again and locked files can cause partial cleanup.
- RemovedContentMB is logical content size, not measured free space. Incoming, Staging, registry state, user data and services are unchanged.
