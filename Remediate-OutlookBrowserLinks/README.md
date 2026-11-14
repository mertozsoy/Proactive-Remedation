# Remediate Outlook Browser Links

Classic Outlook opens web links in Microsoft Edge even when another browser is the Windows default. The setting lives in the user hive, and on Microsoft 365 Business plans the Office policy cannot manage it for Outlook. This pair reads the Outlook link preference and points it back to the Windows default browser.

## Files

| File | Purpose |
|---|---|
| `Detect-OutlookBrowserLinks.ps1` | Runs as the user. Reads the Windows default browser for http, the Office policy value `browserchoice` and the DPAPI protected per-user value `BrowserChoice`. Exits 1 when Outlook is set to Edge while Windows uses another browser. |
| `Remediate-OutlookBrowserLinks.ps1` | Exports the current `Links` key, writes `browserchoice` as 0, rewrites the per-user value with a fresh DPAPI blob and verifies both values. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-OutlookBrowserLinks.ps1` as the detection script and `Remediate-OutlookBrowserLinks.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily. Assign to a user group, not a device group.
5. Start with a pilot group, check the output, then widen the scope.

## Notes

- Both values are per user. The script must run with the logged-on credentials and cannot fix a user who is not signed in.
- `browserchoice` under `HKCU\Software\Policies\Microsoft\Office\16.0\Common\Links` is the documented Office policy value. On Microsoft 365 Business plans that policy is not available for Outlook, so the per-user value is what Outlook reads there. When the value is already 1 the pair reports `PolicyManaged` and leaves it alone. A standard user cannot write that key, so `$SetPolicyValue` is `$false`; deploy the policy through Intune instead.
- The per-user value is DPAPI protected. Writing a plain DWORD to `BrowserChoice` does not work. The script builds the blob with `CryptProtectData` and the description `V2 Microsoft 365 Browser User Choice`.
- Outlook reads the preference at start. If Outlook is open the output ends with `Effective=NextOutlookStart`. Nothing is closed or restarted.
- The previous `Links` key is exported to `%LOCALAPPDATA%\IntuneRemediations\Backup` before the change. Files older than 30 days are removed on the next run.
