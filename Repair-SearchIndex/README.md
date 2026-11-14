# Repair Search Index

Intune Remediations script pair for Windows Search. Start menu and File Explorer search return nothing when the WSearch service is stopped, the indexer process is missing or the index database is gone. This pair checks those three pieces and repairs them without a reboot.

## Files

| File | Purpose |
|---|---|
| `Detect-SearchIndex.ps1` | Reads the WSearch service through CIM, checks the SearchIndexer process and looks for `Windows.db` or `Windows.edb`. Exits 1 when one of them is missing or stopped. |
| `Remediate-SearchIndex.ps1` | Restores the start type, starts the service, restarts the search UI process and moves a missing or empty index database to a backup folder so the indexer builds a new one. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-SearchIndex.ps1` as the detection script and `Remediate-SearchIndex.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily, with a retry of one or two attempts.
5. Assign to a pilot group first, then widen the scope.

## Notes

- The rebuild runs only when the database is missing or empty. Set `$ForceRebuild = $true` to force a full rebuild.
- The old database is moved to `%ProgramData%\IntuneRemediations\Backup\SearchIndex`. Delete old folders when disk space matters.
- `SearchHost.exe` is closed by the script. Windows starts it again on the next search.
- The start type is left alone when a security policy manages the WSearch service.
- Indexing runs in the background after the fix. Results on large profiles can take hours to fill in.
