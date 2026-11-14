# Remove Office Update Leftovers

Retired GPO or Configuration Manager settings can keep Office on an obsolete update source. These scripts identify update overrides, disable approved OfficeMgmtCOM leftovers, and remove exact approved source or channel values after backing them up.

## Files

| File | Purpose |
|---|---|
| `Detect-OfficeUpdateLeftovers.ps1` | Reports OfficeMgmtCOM and nonempty source or channel overrides without exposing their data. |
| `Remediate-OfficeUpdateLeftovers.ps1` | Backs up affected keys, changes approved leftovers, and verifies registry state. |

## Deployment (Intune)

1. Confirm the old Office GPO, local policy, Intune assignment, and deployment configuration no longer manage the targeted values. Set `$RetiredManagementConfirmed = $true` only for that migration scope.
2. Fill `$RetiredUpdatePaths` and `$RetiredUpdateBranches` with exact retired values. Keep all three settings identical in both scripts.
3. Go to **Devices > Manage devices > Scripts and remediations > Create script package** and upload both scripts.
4. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot device group and schedule daily during the migration. Remove the assignment after cleanup.

## Notes

- Changes require ownership confirmation; registry values alone cannot prove a policy is retired. Any ConfigMgr client or Cloud Update policy key blocks changes.
- All nonempty source and channel overrides are candidates, not proof of broken updates. Unlisted values or unexpected types block the entire change.
- OfficeMgmtCOM becomes DWORD 0 in policy and string False in Click-to-Run configuration; only listed UpdatePath, UpdateBranch, and UpdateUrl values are removed.
- Backups are under `%ProgramData%\IntuneRemediations\Backup\OfficeUpdateLeftovers`; restore only reviewed values. CDNBaseUrl and UpdateChannel remain unchanged.
- Fixed verifies registry state only. COM deregistration waits for the next Click-to-Run service start; no service restart, forced app closure, or update installation is performed.
