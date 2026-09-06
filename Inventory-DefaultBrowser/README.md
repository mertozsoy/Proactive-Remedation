# Default Browser Inventory

Intune Proactive Remediation pair used purely for **inventory/reporting** — it does not change anything on the device. It reports which browser is set as the logged-on user's default via Intune's remediation output/log, which can be surfaced in Intune reporting.

## Files

| File | Purpose |
|---|---|
| `Detect-DefaultBrowser.ps1` | Finds the currently logged-on user (via the owner of `explorer.exe`), reads their `UserChoice` registry value for the `http` protocol, and writes out a friendly browser name (Edge, Chrome, Firefox, IE, Opera, Brave, Vivaldi, or the raw ProgId if unrecognized). Always exits `0`. |
| `Remediate-DefaultBrowser.ps1` | No-op stub required by the Proactive Remediation model. Always exits `0`. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context** (needed to read another user's registry hive via `HKEY_USERS`).
4. Review the **Detection script output** column in Intune reporting to see the reported default browser per device.

## Notes

- No environment-specific values are present in these scripts.
- Since detection always exits `0`, this remediation never shows as "non-compliant" — it's designed only to surface data in reports, not to enforce a policy.
