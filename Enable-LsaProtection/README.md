# Enable LSA Protection

Checks explicit RunAsPPL configuration on Windows 11 22H2 or later clients. The remediation sets a missing or disabled value to DWORD 2 without creating a UEFI lock. Existing DWORD 1 or 2 values are preserved.

## Files

| File | Purpose |
|---|---|
| `Detect-LsaProtection.ps1` | Checks OS support, policy evidence and the RunAsPPL registry type and value. |
| `Remediate-LsaProtection.ps1` | Sets missing or zero RunAsPPL to DWORD 2 and reads it back. Does not restart Windows. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-LsaProtection.ps1` and `Remediate-LsaProtection.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for these unsigned files.
4. Validate smart card drivers, password filters and other LSA plug-ins on a pilot group before assignment.
5. Schedule daily. Arrange a normal Windows restart after configuration changes.

## Notes

- Windows 11 build 22621 or later clients only; older Windows and servers are not applicable.
- Registry configuration is not runtime proof. After restart, verify WinInit event 12 in the System log; automatic protection can exist without RunAsPPL.
- ADMX policy evidence or a non-null WMI Bridge configuration value blocks writes, including ambiguous default zero; missing schemas and read failures also block writes.
- Exclude devices managed through Group Policy Preferences or other scripts; those sources cannot be reliably attributed from RunAsPPL alone.
- `$EnableRemediation = $false` by default. Review CodeIntegrity audit events 3065/3066 for incompatible LSA plug-ins, then enable it; no values or keys are deleted.
