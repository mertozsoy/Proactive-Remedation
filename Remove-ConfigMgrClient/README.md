# Remove ConfigMgr Client

ConfigMgr clients can remain after an Intune-only migration. This script pair detects the client and selected residual paths, optionally runs the supported local uninstaller, and reports anything still requiring review.

## Files

| File | Purpose |
|---|---|
| `Detect-ConfigMgrClient.ps1` | Checks CcmExec, running CCMSetup processes and six selected file or registry paths. Returns 1 for findings and 0 for clear selected checks or unsupported scope. |
| `Remediate-ConfigMgrClient.ps1` | Starts in report mode. After explicit approval, validates the local uninstaller signature, runs `/uninstall`, waits and verifies. Never manually deletes residuals. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-ConfigMgrClient.ps1` and `Remediate-ConfigMgrClient.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for these unsigned drafts; follow your signing requirements before production.
4. Assign only to a pilot device group approved for Intune-only migration. Exclude devices that still need ConfigMgr or co-management. Start with an on-demand pilot, then use a daily schedule during migration.
5. Keep `$EnableRemediation = $false` and `$IntuneOnlyMigrationApproved = $false` for initial reporting. Enable both only after completing the prerequisites below. These switches attest approval for every targeted device; they do not validate readiness.

## Notes

- Medium impact: removal can interrupt application and update management. Verify Intune-only readiness, retire reinstall assignments and exclude active co-managed devices. Validate removal in a pilot group first.
- `$EnableRemediation` and `$IntuneOnlyMigrationApproved` default to `$false`. Set both to `$true` in remediation only after approval for every targeted device; the flags do not verify migration readiness.
- Only the local Microsoft-signed `%windir%\ccmsetup\ccmsetup.exe /uninstall` is used. Residual cleanup stays report only; policy, registry keys and folders are not forcibly changed. Rollback requires a separately approved client installation.
- `Busy` leaves CCMSetup untouched. A timeout does not kill it; review before retrying. Only return code 0 proceeds to verification. Residuals return `NeedsReview` and exit 1 even after uninstall; `Healthy` covers selected checks only.
- Requires Windows clients and 64-bit PowerShell 5.1. No restart or sign-out is forced. Logs: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT_ConfigMgrClient.log` and `%windir%\ccmsetup\logs\CCMSetup.log`.
