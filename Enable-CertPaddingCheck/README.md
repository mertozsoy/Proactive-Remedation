# Enable Cert Padding Check

Windows verifies Authenticode signatures through WinVerifyTrust. The stricter padding check for CVE-2013-3900 is opt-in. There is no settings catalog entry for it, so devices stay open in Defender vulnerability reports until the registry value exists. These scripts read both registry locations and set EnableCertPaddingCheck to 1.

## Files

| File | Purpose |
|---|---|
| `Detect-CertPaddingCheck.ps1` | Reads EnableCertPaddingCheck in the native and Wow6432Node locations. Exits 1 when a required value is missing or not 1. |
| `Remediate-CertPaddingCheck.ps1` | Exports the existing keys to a backup folder and writes EnableCertPaddingCheck as REG_SZ 1. Verifies both locations after the write. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-CertPaddingCheck.ps1` as detection and `Remediate-CertPaddingCheck.ps1` as remediation.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
4. Schedule: Daily.
5. Assign to a pilot group first. Test installers and signed line of business tools on those devices before widening the scope.

## Notes

- Microsoft documents the value as REG_SZ with data 1 under `HKLM\SOFTWARE\Microsoft\Cryptography\Wintrust\Config`.
- 64-bit Windows also needs the same value under `HKLM\SOFTWARE\Wow6432Node\Microsoft\Cryptography\Wintrust\Config` for 32-bit callers.
- The new behavior applies after a restart. The script never restarts the device.
- Existing keys are exported to `%ProgramData%\IntuneRemediations\Backup` before the value is written.
- Non-conforming installers may appear unsigned after the change. Logs: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT_CertPaddingCheck.log`.
