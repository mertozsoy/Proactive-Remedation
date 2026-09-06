# Update TightVNC

Intune Proactive Remediation pair that keeps **TightVNC** current using `winget`. As with the Java Runtime remediation, the actual upgrade happens in the **detection** script; the remediation script is a logging stub.

## Files

| File | Purpose |
|---|---|
| `Detect-TightVNCUpdate.ps1` | Finds the installed TightVNC version from the uninstall registry keys. If not installed, reports compliant. If installed, queries `winget show --id GlavSoft.TightVNC` for the latest available version; if outdated, stops running TightVNC processes (`tvnserver`, `tvnviewer`, `tvnservice`) and runs `winget upgrade` immediately, then re-verifies. Exits `0` on success, `1` on failure. Logs to `C:\Temp\IntunePR-TightVNC-Detection.log`. |
| `Remediate-TightVNCUpdate.ps1` | No-op stub that logs that remediation was already handled in detection. Always exits `0`. Logs to `C:\Temp\IntunePR-TightVNC-Remediation.log`. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context** (required for `winget` machine-wide operations and `HKLM` access).
4. Requires `winget` (Microsoft.DesktopAppInstaller) to be present on the device.

## Notes

- No environment-specific values are present in these scripts. `GlavSoft.TightVNC` is TightVNC's public winget package ID, not a secret.
- Stopping `tvnserver` briefly interrupts any active remote-control sessions to the device during the upgrade.
