# Repair TaskCache

Missing task files can leave orphaned Task Scheduler cache records and break task enumeration. These scripts find missing-file records and remove approved entries after backup. They do not recreate missing tasks.

## Files

| File | Purpose |
|---|---|
| `Detect-TaskCache.ps1` | Compares Tree IDs, Tasks paths and task files, then checks Get-ScheduledTask. |
| `Remediate-TaskCache.ps1` | Backs up TaskCache and task files, removes approved orphan records and verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-TaskCache.ps1` and `Remediate-TaskCache.ps1`.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Keep cleanup disabled for the initial pilot. Review orphan GUIDs in the device log against TaskCache and confirm they are not policy-managed.
5. Set `$EnableRemediation = $true` and populate `$ApprovedOrphanIds` with reviewed GUIDs including braces. Schedule daily for the approved pilot group.

## Notes

- Registry cleanup defaults to disabled. Microsoft task paths stay protected; keep protection prefixes identical in both scripts.
- Only missing-file entries with a matching Tree ID and Tasks path are removed. Inconsistent records require manual review.
- Never approve Intune or GPO-managed tasks. Restore required tasks through their owning application or management policy.
- Backup location: `%ProgramData%\IntuneRemediations\Backup\TaskCache`. Backup access is restricted to SYSTEM and administrators; recovery is supervised.
- At most five entries are removed per run. Avoid concurrent task changes. No service restart or reboot occurs; failed enumeration stays a failure.
