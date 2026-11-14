# Set Point and Print Security

Checks approved print servers and restores secure Point and Print values on domain-joined Windows clients. Keeps administrator-only driver installation enabled and maintains both standard and package-aware server lists.

## Files

| File | Purpose |
|---|---|
| `Detect-PointAndPrintSecurity.ps1` | Compares registry types, security values and approved server lists. Returns 1 for drift. |
| `Remediate-PointAndPrintSecurity.ps1` | Backs up existing printer policy settings, applies the baseline and verifies it. |

## Deployment (Intune)

1. Set `$ApprovedPrintServers` to the same approved FQDNs in both scripts.
2. Check Settings Catalog, security baselines and local/domain GPOs. Remove overlapping assignments before setting `$ConfirmNoCentralPolicy = $true` in the remediation script.
3. Go to **Devices > Scripts and remediations > Remediations > Create** and select both scripts.
4. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot device group and schedule daily.

## Notes

- `$ConfirmNoCentralPolicy` defaults to false. Drift stays blocked until ownership is confirmed; registry values alone cannot identify the active manager.
- Requires supported, fully patched domain-joined Windows clients. Other devices return `NotApplicable`.
- Sets administrator restriction to 1 and both prompt values to 0. It does not remove elevation prompts or install drivers.
- Replaces both approved lists, including obsolete package-aware entries. Existing printers are not removed; this is not a firewall restriction.
- Existing settings are exported to `%ProgramData%\IntuneRemediations\Backup`. Verification checks registry state, not a print job; no restart is performed.
