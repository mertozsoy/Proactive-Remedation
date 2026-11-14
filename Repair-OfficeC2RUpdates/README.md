# Repair Office C2R Updates

Microsoft 365 Apps can keep using an obsolete update source even while its scheduled task runs. These scripts check a configured source and minimum installed build, repair the local source, and refresh Office update detection through its existing task.

## Files

| File | Purpose |
|---|---|
| `Detect-OfficeC2RUpdates.ps1` | Checks the local update source, installed inventory version, and Office Automatic Updates 2.0 task health. |
| `Remediate-OfficeC2RUpdates.ps1` | Backs up registry settings, repairs the configured source, clears the detection timestamp, enables the existing task if disabled, and runs it. Verifies task completion and the configured minimum build. |

## Deployment (Intune)

1. Set `$ApprovedUpdateUrl` to your approved HTTPS update source and `$MinimumVersion` to a supported build for the intended channel. Keep both scripts identical. Blank values skip the corresponding check.
2. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
3. Upload the detection and remediation scripts.
4. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot device group and schedule daily.

## Notes

- Defaults check task health only, with a seven-day stale threshold. Set a minimum build to detect old installations whose task still runs successfully.
- Office update policy values, Cloud Update policy values, OfficeMgmtCOM, or an installed ConfigMgr client exclude the device without changes. Fix managed settings at their source.
- Only Microsoft 365 Apps for enterprise or business is targeted. Missing inventory or update tasks requires separate Office repair; a stopped Click-to-Run service is not changed.
- Source changes require an explicit approved URL and may change channel. Registry backups go to `%ProgramData%\IntuneRemediations\Backup`; restore only reviewed values if rolling back.
- `Pending` exits 1. Task completion alone does not prove installation; the configured minimum build is checked through Office inventory. No forced app closure or restart is requested; existing Office deadlines still apply.
