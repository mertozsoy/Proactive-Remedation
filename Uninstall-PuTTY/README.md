# Uninstall PuTTY (release 0.83, 64-bit)

Intune Proactive Remediation script pair that detects and silently removes **PuTTY release 0.83 (64-bit)** from Windows devices.

## Files

| File | Purpose |
|---|---|
| `Detect-PuTTY.ps1` | Checks the uninstall registry keys for the PuTTY product GUID. Exits `1` if found, `0` if not found. |
| `Remediate-PuTTY.ps1` | Silently uninstalls via `msiexec.exe /X <GUID> /quiet /norestart` and logs each step to `C:\Temp\PuTTY_release_0.83_(64-bit)_Removal.log`. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload `Detect-PuTTY.ps1` as the detection script and `Remediate-PuTTY.ps1` as the remediation script.
3. Run in the **system context**.
4. Assign to the target device group.

## Notes

- No environment-specific values are present in these scripts.
- Update `$AppGUID` if targeting a different PuTTY version (each release has its own MSI product code).
