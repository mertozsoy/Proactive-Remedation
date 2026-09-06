# Update Adobe Acrobat Reader DC

Intune Proactive Remediation pair that keeps **Adobe Acrobat Reader DC** current using `winget`. As with the Java Runtime remediation, the actual upgrade happens in the **detection** script; the remediation script is a logging stub.

## Files

| File | Purpose |
|---|---|
| `Detect-AcrobatDCUpdate.ps1` | Finds the installed Acrobat Reader DC version from the uninstall registry keys. If not installed, reports compliant. If installed, queries `winget show --id XPDP273C0XHQH2` for the latest available version; if outdated, stops running Acrobat processes and runs `winget upgrade` immediately, then re-verifies. Exits `0` on success, `1` on failure. Logs to `C:\Temp\IntunePR-AcrobatDC-Detection.log`. |
| `Remediate-AcrobatDCUpdate.ps1` | No-op stub that logs that remediation was already handled in detection. Always exits `0`. Logs to `C:\Temp\IntunePR-AcrobatDC-Remediation.log`. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context** (required for `winget` machine-wide operations and `HKLM` access).
4. Requires `winget` (Microsoft.DesktopAppInstaller) to be present on the device.

## Notes

- No environment-specific values are present in these scripts. `XPDP273C0XHQH2` is Adobe Acrobat Reader DC's public winget package ID, not a secret.
