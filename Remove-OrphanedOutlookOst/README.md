# Remove Orphaned Outlook OST Files

Recreating classic Outlook profiles can leave unused OST files on disk. These scripts report aged files and delete only administrator-approved files after verifying their names and SHA256 hashes. They do not infer orphan status from age or numbered filenames.

## Files

| File | Purpose |
|---|---|
| `Detect-OrphanedOutlookOst.ps1` | Reports aged OST counts, approved matches and files requiring review. |
| `Remediate-OrphanedOutlookOst.ps1` | Deletes approved aged OST files when enabled and verifies their absence. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Upload both scripts. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
3. Keep `$RemoveFiles = $false` initially. Review candidates locally against Data Files in every classic Outlook profile, including unused profiles. Confirm no profile references a candidate. Preserve any unsynchronized or local-only data before approving deletion.
4. Add entries to `$ApprovedOstFiles` in both scripts using `@{ Name = 'retired.ost'; SHA256 = '<actual 64-character SHA256>' }`. Obtain each hash with `Get-FileHash -LiteralPath <reviewed-file> -Algorithm SHA256`. Keep both approval lists and `$MinimumAgeDays` identical. Scope approvals to the reviewed users and devices.
5. Set `$RemoveFiles = $true` in the remediation script only after approval. Assign to a pilot user group and schedule daily. Have users close Outlook and Word themselves.

## Notes

- Default scope is direct `.ost` files in `%LOCALAPPDATA%\Microsoft\Outlook`, unchanged for at least 30 days; custom locations and PST files are excluded.
- Automatic cross-profile orphan detection is not implemented; unapproved aged files remain review-only, even when deletion is enabled.
- Outlook, new Outlook or Word running in any session defers removal; processes are never stopped. Reparse paths, locked files and changed hashes are not deleted.
- Deletion is permanent. Only server-backed, unused files with preserved local-only data should be approved; age or a numeric suffix is not proof of a duplicate.
- `ReportOnly`, `Deferred`, `NeedsReview` and aged candidates return 1. Logs contain counts only at `%LOCALAPPDATA%\IntuneRemediations\Logs\IRT_OrphanedOutlookOst.log`; hashing large approved files can take time.
