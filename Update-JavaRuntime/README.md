# Update Java Runtime

Intune Proactive Remediation pair that keeps **Oracle Java Runtime Environment (Java 8)** current using `winget`. Unusually, the actual upgrade happens in the **detection** script; the remediation script is a logging stub, since the detection script already performs the fix in the same run.

## Files

| File | Purpose |
|---|---|
| `Detect-JavaRuntimeUpdate.ps1` | Finds the installed "Java 8 Update" version from the uninstall registry keys. If not installed, reports compliant. If installed, queries `winget show` for the latest available version; if outdated, stops running Java processes and runs `winget upgrade` immediately, then re-verifies. Exits `0` on success, `1` on failure. Logs to `C:\Temp\IntunePR-Java-Detection.log`. |
| `Remediate-JavaRuntimeUpdate.ps1` | No-op stub that logs that remediation was already handled in detection. Always exits `0`. Logs to `C:\Temp\IntunePR-Java-Remediation.log`. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context** (required for `winget` machine-wide operations and `HKLM` access).
4. Requires `winget` (Microsoft.DesktopAppInstaller) to be present on the device.

## Notes

- No environment-specific values are present in these scripts.
- Only targets the classic "Java 8 Update" MSI-based installs; does not manage other JRE/JDK vendors or versions.
