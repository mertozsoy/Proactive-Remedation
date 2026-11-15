# Remove Blocklisted Root CAs

Finds explicitly blocklisted certificates in the LocalMachine Root store. After approval, remediation backs up and removes matching unmanaged roots, then verifies their absence. It does not classify unknown or expired certificates as malicious.

## Files

| File | Purpose |
|---|---|
| `Detect-BlocklistedRootCAs.ps1` | Matches SHA1 thumbprints and reports protected roots. |
| `Remediate-BlocklistedRootCAs.ps1` | Exports certificate and registry backups, removes approved roots, and checks the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Set identical `$BlocklistedThumbprints` and `$ApprovedUnmanagedThumbprints` lists in both scripts. Use exact 40-character SHA1 thumbprints from your security review.
3. Confirm removal targets are not actively deployed by Intune, GPO, enterprise trust, or another management tool before adding them to `$ApprovedUnmanagedThumbprints`. Review policy ownership centrally; the script cannot discover every deployment source.
4. Upload the detection and remediation scripts. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**, unless you sign the scripts.
5. Assign a pilot group and schedule daily. After checking dependencies, set `$EnableRemediation = $true` to allow removal.

## Notes

- Empty blocklists return `NotApplicable`; disabled remediation reports matches and exits 1.
- GPO roots, unapproved ownership, nonlocal roots, and roots with private keys are protected. Resolve managed certificates at their deployment source.
- Backups are stored under `%ProgramData%\IntuneRemediations\Backup\BlocklistedRootCAs`. Backup failure prevents removal; restore a reviewed `.cer` to LocalMachine Root only with security approval.
- Removing a required root can break TLS, VPN, Wi-Fi, or management connectivity. CurrentUser roots and other stores are untouched.
- This removes existing trust entries, not future installation rights or the Microsoft trust lists. Address software or policy that reinstalls a root.
