# Disable Legacy TLS

Intune Remediations script pair. TLS 1.0 and TLS 1.1 stay enabled on many devices, and older .NET Framework apps still pick them by default. This pair disables both protocols in SCHANNEL and makes .NET follow the OS TLS defaults.

## Files

| File | Purpose |
|---|---|
| `Detect-LegacyTls.ps1` | Checks `Enabled=0` and `DisabledByDefault=1` under `SCHANNEL\Protocols\TLS 1.0` and `TLS 1.1` (Client, and Server when `$IncludeServerSide` is on). Checks `SchUseStrongCrypto=1` and `SystemDefaultTlsVersions=1` for the 64-bit and 32-bit .NET Framework keys that exist. |
| `Remediate-LegacyTls.ps1` | Writes the same values, reads them back and reports the result. SCHANNEL changes take effect after the next restart. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-LegacyTls.ps1` as the detection script and `Remediate-LegacyTls.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Old printers, scanners, internal web apps and some VPN clients may still need TLS 1.0 or 1.1. Test with a pilot group before a wide rollout.
- The script does not restart the device. The new SCHANNEL settings apply after the next restart.
- Set `$IncludeServerSide = $false` if you only want to change the client side.
- `$DotNetVersions` covers .NET Framework 4.x (`v4.0.30319`) and 3.5 (`v2.0.50727`). Missing keys are skipped.
