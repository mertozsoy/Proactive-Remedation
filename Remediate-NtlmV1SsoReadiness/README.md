# Remediate NTLMv1 SSO Readiness

Intune Remediations script pair. Windows is moving NTLMv1 derived SSO (MS-CHAPv2, used by some Wi-Fi and VPN setups) from audit to enforce through the BlockNtlmv1SSO setting. This pair shows which devices still use it and lets you give a time limited audit exception to the ones that need more time.

## Files

| File | Purpose |
|---|---|
| `Detect-NtlmV1SsoReadiness.ps1` | Reads BlockNtlmv1SSO and events 4024 and 4025 from the last `$EventLookbackDays` days. Exits `1` when an approved exception has to be applied or an expired one has to be removed. |
| `Remediate-NtlmV1SsoReadiness.ps1` | Writes the Audit value (`0`) until the date in `$ExceptionApprovedUntil`, capped at `$MaxExceptionDays` (90). Removes it when the date passes. An exception without an end date is never created. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-NtlmV1SsoReadiness.ps1` as the detection script and `Remediate-NtlmV1SsoReadiness.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Leave `$ExceptionApprovedUntil` empty to use the package as a report only.
- A value set by policy is reported as ExceptionOverridden and not changed.
- Log: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT-REM-005.log`
