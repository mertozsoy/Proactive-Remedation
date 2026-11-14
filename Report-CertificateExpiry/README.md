# Report Certificate Expiry

Detection only script for Intune Remediations. An expired Wi-Fi, VPN or SCEP certificate cuts the user off, and an expired Intune MDM certificate stops the device from syncing. This script reports them before that happens.

## Files

| File | Purpose |
|---|---|
| `Detect-CertificateExpiry.ps1` | Checks the Intune MDM device certificate and every LocalMachine\My certificate with a private key that expires within `$WarnDays` (30). Exits `1` when it finds one. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-CertificateExpiry.ps1` as the detection script. Leave the remediation script empty.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Detection only. Use `$IgnoreIssuerRegex` to skip self-signed or helper certificates.
