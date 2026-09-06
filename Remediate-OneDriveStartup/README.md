# Remediate OneDrive Startup Registry Entry

Intune Proactive Remediation script pair that ensures OneDrive is configured to launch automatically at sign-in by checking (and repairing) the `Run` registry value.

## Files

| File | Purpose |
|---|---|
| `Detect-OneDriveStartup.ps1` | Verifies `OneDrive.exe` exists, resolves the correct `Run` key (per-user hive under `HKEY_USERS` when running as SYSTEM, or `HKCU` otherwise), and checks whether the `OneDrive` startup value matches the expected command line. Exits `1` if missing/incorrect, `0` if compliant. |
| `Remediate-OneDriveStartup.ps1` | Creates or corrects the `OneDrive` startup registry value so `OneDrive.exe /background` runs at logon. Always exits `0`. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context** (script resolves the active logged-on user's SID and edits `HKEY_USERS` directly, so it works without "run as logged-on user").
4. Assign to the target device group.

## Notes

- No environment-specific values are present in these scripts.
- Assumes the default 64-bit OneDrive per-machine install path; adjust `$OneDrivePath` / `$RunValueData` if your OneDrive deployment uses a different location.
