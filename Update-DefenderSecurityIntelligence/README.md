# Update Defender Security Intelligence

Intune Remediations script pair. Devices that are often offline, on VPN or behind a broken update source keep old Defender signatures for days.

## Files

| File | Purpose |
|---|---|
| `Detect-DefenderSecurityIntelligence.ps1` | Checks the signature age against `$MaxSignatureAgeDays` (2) and reports running mode, real-time protection, engine and platform versions. |
| `Remediate-DefenderSecurityIntelligence.ps1` | Tries the default source, Microsoft Update and MMPC in order, then `MpCmdRun -SignatureUpdate` as a fallback. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-DefenderSecurityIntelligence.ps1` as the detection script and `Remediate-DefenderSecurityIntelligence.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Real-time protection is only reported, never changed.
