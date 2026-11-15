# Set Defender Network Protection

Microsoft Defender network protection blocks connections to malicious domains and IP addresses for every process. On some devices the feature is off or still in audit mode, so traffic is logged but not blocked. This pair reads the effective state and sets block mode when no policy owns the setting.

## Files

| File | Purpose |
|---|---|
| `Detect-DefenderNetworkProtection.ps1` | Reads `EnableNetworkProtection` from `Get-MpPreference`, checks the policy registry values, and reports state with its source. |
| `Remediate-DefenderNetworkProtection.ps1` | Sets block mode with `Set-MpPreference` or writes the policy value when `$OverridePolicy` is enabled, then reads the state back. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-DefenderNetworkProtection.ps1` as the detection script and `Remediate-DefenderNetworkProtection.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, review the detection output, then widen the scope.

## Notes

- Block mode can cut a line of business application that reaches a flagged domain. Review audit events 1125 before a wide rollout.
- Devices where Group Policy or Intune policy owns the value stay in report mode. Set `$OverridePolicy = $true` to write the Group Policy registry value; the Intune policy path is never written by the script.
- Defender in passive mode is reported as not applicable because the feature is not enforced on those devices.
- Registry values are exported with `reg.exe` to `%ProgramData%\IntuneRemediations\Backup` before any write.
- `$EnableRemediation` is `$true`. Set it to `$false` to keep the pair in reporting mode.
