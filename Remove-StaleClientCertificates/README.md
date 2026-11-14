# Remove Stale Client Certificates

Old SCEP or PKCS device certificates can complicate Wi-Fi or VPN certificate selection. These scripts remove explicitly approved obsolete certificates from LocalMachine My while retaining a verified replacement reference and all private keys.

## Files

| File | Purpose |
|---|---|
| `Detect-StaleClientCertificates.ps1` | Checks the retained certificate and reports approved obsolete certificates. |
| `Remediate-StaleClientCertificates.ps1` | Backs up and removes approved expired certificates; optionally removes approved unexpired duplicates. |

## Deployment (Intune)

1. Confirm the replacement works with the intended Wi-Fi or VPN profile. Confirm the obsolete certificates belong to the same SCEP or PKCS profile and are no longer required by any active assignment or certificate binding.
2. Set `$KeepThumbprint` and `$ObsoleteThumbprints` identically in both scripts using 40-character hexadecimal thumbprints without spaces. Target only the device that owns those certificates. Empty configuration fails closed.
3. Go to **Devices > Scripts and remediations > Remediations > Create**. Upload the detection and remediation scripts.
4. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**, unless signed for your environment.
5. Assign to a pilot device group. Run daily and review results before expanding.

## Notes

- Device certificates only; user stores, root stores and enrollment certificates are outside the approved scope. Never list MDM enrollment certificates.
- Replacement checks cover dates, private-key presence and Client Authentication EKU; matching subject and issuer do not prove template, SAN, trust, revocation or network acceptance.
- `$RemoveUnexpiredDuplicates = $false` protects unexpired certificates; approved expired entries are removed by default. Blocked entries return exit 1.
- Public CER backups go to `%ProgramData%\IntuneRemediations\Backup\StaleClientCertificates`; private keys stay in place. CER files are not full private-key recovery backups.
- Active policies and network profiles are not changed. If obsolete certificates return, correct the issuing assignment rather than repeatedly expanding the removal list.
