# Remove CBS Log Files

Intune Remediations script pair. The CBS log folder under `C:\Windows\Logs\CBS` keeps every rotated copy of the servicing log. On devices with a servicing loop the folder reaches tens of GB and the system disk fills. This pair measures the folder, then deletes the old `CbsPersist` files.

## Files

| File | Purpose |
|---|---|
| `Detect-CbsLogFiles.ps1` | Measures the folder, the `CbsPersist_*` archives and the active `CBS.log`. `$FolderSizeLimitMB`, `$ArchiveSizeLimitMB` and `$MaxArchiveFiles` set the limits. |
| `Remediate-CbsLogFiles.ps1` | Deletes `CbsPersist_*` files older than `$MinFileAgeDays`, keeps the newest `$KeepNewestArchives` files, then measures again. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-CbsLogFiles.ps1` as the detection script and `Remediate-CbsLogFiles.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**.
4. Run script in 64-bit PowerShell: **Yes**. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- `CbsPersist` files are rotated copies of `CBS.log`. They hold past servicing sessions only.
- The active `CBS.log` is removed only when the Windows Modules Installer service is stopped. Windows starts a new file on the next servicing run.
- `$RemoveArchiveFiles = $false` and `$TrimActiveLog = $false` turn the cleanup off and leave the script reporting only.
- Files held open by another process are skipped and retried on the next run. The folder itself is never deleted.
- A folder that grows back points to a servicing problem. Cleaning log files does not fix that.
