# Remediate Outlook OST Size

Classic Outlook keeps a local OST file per profile and caches shared mailboxes in the same file by default. A mailbox with many shared folders or a long sync window can push that file toward the 50 GB limit. These scripts measure the OST files of loaded profiles and set the shared folder cache policy for profiles that have no value.

## Files

| File | Purpose |
|---|---|
| `Detect-OutlookOstSize.ps1` | Reads `DownloadSharedFolders` from the Cached Mode policy of every loaded profile and measures the OST files under the user's Outlook folder. Exits 1 when the value is missing or a file is at 95 percent of the limit. |
| `Remediate-OutlookOstSize.ps1` | Writes `DownloadSharedFolders=0` when the value is absent and verifies it. Existing values are left unchanged. Can remove OST files when `$RemoveOstFiles` is set to `$true`. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-OutlookOstSize.ps1` as the detection script and `Remediate-OutlookOstSize.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: No.
4. Schedule: Daily.
5. Assign to a pilot group. Keep `$RemoveOstFiles` at `$false` for the first runs and decide on file removal after the results are reviewed.

## Notes

- Runs as SYSTEM and reads the policy hive of loaded profiles only. A user who is signed out is processed at a later run.
- `DownloadSharedFolders=0` is written only when the value is absent. A value that is already present, including `1`, is reported as policy managed and is not changed.
- Shared mailbox items stay on the server. Users need a connection to open them. The primary mailbox cache is not touched.
- `$RemoveOstFiles` is off by default. When enabled, files that are open are skipped and Outlook rebuilds the OST at the next start.
- The size check uses the documented 50 GB `MaxLargeFileSize` default or a lower policy value when one exists.
