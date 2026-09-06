# Uninstall Firefox

Intune Proactive Remediation script pair that detects and silently removes **Mozilla Firefox** from Windows devices via its native uninstaller.

## Files

| File | Purpose |
|---|---|
| `Detect-FirefoxUninstall.ps1` | Checks the uninstall registry keys and the Program Files path for Mozilla Firefox. Exits `1` if found, `0` if not found. |
| `Remediate-FirefoxUninstall.ps1` | Stops running Firefox processes and silently runs `Mozilla Firefox\uninstall\helper.exe -ms`. Self-elevates if not already running as administrator and relaunches in 64-bit PowerShell if needed. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload `Detect-FirefoxUninstall.ps1` as the detection script and `Remediate-FirefoxUninstall.ps1` as the remediation script.
3. Configure: **Run this script using the logged-on credentials = No**, **Run script in 64-bit PowerShell = Yes**.
4. Assign to the target device group.

## Notes

- No environment-specific values are present in these scripts.
- Uses Firefox's own uninstaller (`helper.exe -ms`) rather than an MSI product code, so it works regardless of installed version.
