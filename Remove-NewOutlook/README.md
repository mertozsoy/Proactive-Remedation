# Remove New Outlook

New Outlook can appear after a Windows 11 upgrade where only classic Outlook is approved. These scripts detect Microsoft.OutlookForWindows for all users and in provisioning, remove it after approval, and verify that it is absent.

## Files

| File | Purpose |
|---|---|
| `Detect-NewOutlook.ps1` | Counts all-user installations and provisioned entries. Returns 1 when either remains. |
| `Remediate-NewOutlook.ps1` | Removes provisioning and remaining all-user installations, then checks both again. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-NewOutlook.ps1` and `Remediate-NewOutlook.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
4. Review local data risks and set `$AllowAppRemoval = $true` in the remediation script to approve removal.
5. Assign to a pilot device group where every user must use classic Outlook. Exclude devices receiving required new Outlook deployments. Schedule daily.

## Notes

- Windows 11 24H2 or later clients only. Keep `$MinimumWindowsBuild` identical in both scripts; older systems and servers are skipped.
- Removal is off by default because uninstalling can delete local app data. Confirm synchronization and recovery needs before approval.
- A running new Outlook session defers removal. No process is stopped and no restart is initiated.
- Classic Outlook, default associations, Start pins and migration policies are unchanged. Configure these separately; installation origin and user eligibility are not inferred.
- Deprovisioning addresses Windows preinstallation, not Store or managed redeployment. Resolve conflicting assignments before use; rollback requires reinstalling new Outlook.
