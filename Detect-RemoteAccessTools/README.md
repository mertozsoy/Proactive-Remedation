# Detect Remote Access Tools

Detection only script for Intune Remediations. AnyDesk, TeamViewer, RustDesk, ScreenConnect and similar tools are often installed without approval, and portable copies never appear in Discovered apps. This detection script finds them.

## Files

| File | Purpose |
|---|---|
| `Detect-RemoteAccessTools.ps1` | Checks machine and per user uninstall keys (unloaded profiles are mounted for the check), running processes and services against 20 tool patterns. Approved tools go into `$AllowList`. Exits `1` when a tool is found. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-RemoteAccessTools.ps1` as the detection script. Leave the remediation script empty.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Detection only. Removing a remote access tool should be a decision, not an automatic action.
- Combine it with Defender for Endpoint indicators or AppLocker to block the tools.
