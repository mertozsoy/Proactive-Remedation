# Report MDM Device Certificates

Detection only script for Intune Remediations. Old Intune MDM device certificates can pile up in the local machine store after renewals and re-enrollments. Company Portal and VPN clients can then pick the wrong one. This script reports devices with duplicate or expired MDM device certificates.

## Files

| File | Purpose |
|---|---|
| `Detect-MdmDeviceCertificates.ps1` | Counts valid and expired certificates in `Cert:\LocalMachine\My` for each issuer in `$Issuers`. Flags more than `$MaxValidPerIssuer` valid certificates, expired leftovers and the case where no valid certificate is left. Thumbprints and dates go to the log file only. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-MdmDeviceCertificates.ps1` as the detection script. Leave the remediation script empty.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Report only. The script never removes a certificate. Deleting the wrong MDM certificate breaks the enrollment, so cleanup stays a manual decision.
- Devices without any certificate from the listed issuers return NotApplicable.
- Use the thumbprints in the log file to compare with the certificate the device actually uses before removing anything by hand.
- Add or remove issuer names in `$Issuers` to match what you see in your tenant.
