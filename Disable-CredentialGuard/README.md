# Disable Credential Guard

Intune Proactive Remediation **remediation-only** script that disables Windows Credential Guard by clearing the LSA configuration flag.

## Files

| File | Purpose |
|---|---|
| `Remediate-CredentialGuard.ps1` | Sets `HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\LsaCfgFlags` to `0` (disabled), logging a transcript to `C:\Temp\CredentialGuardDetection.txt`. Exits `0` on success, `1` on error. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload `Remediate-CredentialGuard.ps1` as the remediation script.
3. Pair it with a detection script that checks the same `LsaCfgFlags` registry value (exit `1` when it isn't `0`) so the pair only remediates non-compliant devices.
4. Run in the **system context** (required for `HKLM` write access).
5. **A reboot is required** for the Credential Guard state change to take effect — this script only sets the registry flag, it does not restart the device.

## Notes

- No environment-specific values are present in this script.
- Disabling Credential Guard reduces protection against credential theft attacks (e.g. pass-the-hash) — confirm this is an intended security posture change before deploying broadly.
