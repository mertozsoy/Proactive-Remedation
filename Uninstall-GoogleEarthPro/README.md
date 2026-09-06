# Uninstall Google Earth Pro

Intune Proactive Remediation script pair that detects and silently removes **Google Earth Pro** from Windows devices.

## Files

| File | Purpose |
|---|---|
| `Detect-GoogleEarthPro.ps1` | Checks the uninstall registry keys (64-bit and WOW6432Node) for the Google Earth Pro product GUID. Exits `1` (non-compliant) if found, `0` (compliant) if not found. |
| `Remediate-GoogleEarthPro.ps1` | Re-checks for the product GUID and, if present, silently uninstalls it via `msiexec.exe /X <GUID> /quiet /norestart`. Logs each step (start, found/not found, exit code, final result) to `C:\Temp\Google_Earth_Pro_Removal.log`. |

## How it works

1. Both scripts search `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall` and the `WOW6432Node` equivalent for the product code `{E3B69BB6-FFD8-441C-933E-BB8A3136ED8F}`.
2. The Detect script reports compliance state only (no changes made).
3. The Remediate script runs the MSI uninstall, waits for completion, waits 10 seconds, then verifies the key is gone and logs success/failure.

## Deployment (Intune)

1. Create a new **Proactive Remediation** (Remediation script) in Intune.
2. Upload `Detect-GoogleEarthPro.ps1` as the detection script.
3. Upload `Remediate-GoogleEarthPro.ps1` as the remediation script.
4. Run in the **system context** (required for `HKLM` access and `msiexec`).
5. Assign to the target device group and set a run schedule.

## Notes

- No environment-specific values (IPs, credentials, hostnames) are present in these scripts — they are safe to run as-is in any tenant.
- Update the `$AppGUID` value if targeting a different Google Earth Pro release with a different product code (verify via `Get-ChildItem` on the uninstall registry paths on an affected machine).
