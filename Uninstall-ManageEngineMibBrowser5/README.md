# Uninstall ManageEngine MibBrowser 5

Intune Proactive Remediation script pair that detects and silently removes **ManageEngine MibBrowser 5** from Windows devices.

## Files

| File | Purpose |
|---|---|
| `Detect-ManageEngineMibBrowser5.ps1` | Checks the uninstall registry keys (64-bit and WOW6432Node) for the ManageEngine MibBrowser 5 product GUID. Exits `1` (non-compliant) if found, `0` (compliant) if not found. |
| `Remediate-ManageEngineMibBrowser5.ps1` | Re-checks for the product GUID and, if present, silently uninstalls it via `msiexec.exe /X <GUID> /quiet /norestart`. Logs each step (start, found/not found, exit code, final result) to `C:\Temp\ManageEngine_MibBrowser_5_Removal.log`. |

## How it works

1. Both scripts search `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall` and the `WOW6432Node` equivalent for the product code `{9C79392A-ACA0-4253-A57A-B29A53205273}`.
2. The Detect script reports compliance state only (no changes made).
3. The Remediate script runs the MSI uninstall, waits for completion, waits 10 seconds, then verifies the key is gone and logs success/failure.

## Deployment (Intune)

1. Create a new **Proactive Remediation** (Remediation script) in Intune.
2. Upload `Detect-ManageEngineMibBrowser5.ps1` as the detection script.
3. Upload `Remediate-ManageEngineMibBrowser5.ps1` as the remediation script.
4. Run in the **system context** (required for `HKLM` access and `msiexec`).
5. Assign to the target device group and set a run schedule.

## Notes

- No environment-specific values (IPs, credentials, hostnames) are present in these scripts — they are safe to run as-is in any tenant.
- Update the `$AppGUID` value if targeting a different MibBrowser release with a different product code (verify via `Get-ChildItem` on the uninstall registry paths on an affected machine).
