# Disable LLMNR and NetBIOS

Intune Remediations script pair. LLMNR and NetBIOS over TCP/IP make it easy to capture NTLM hashes on a local network. Settings Catalog can turn LLMNR off, but NetBIOS is set per adapter and new adapters come with it enabled. This pair keeps both off.

## Files

| File | Purpose |
|---|---|
| `Detect-LLMNR-NetBIOS.ps1` | Checks the `EnableMulticast` policy value and `NetbiosOptions` on every NetBT interface. Exits `1` if either is enabled. |
| `Remediate-LLMNR-NetBIOS.ps1` | Sets `EnableMulticast` to `0` and `NetbiosOptions` to `2` on every interface. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-LLMNR-NetBIOS.ps1` as the detection script and `Remediate-LLMNR-NetBIOS.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Test old NAS devices and printers that still rely on NetBIOS names before a wide rollout.
- `$CheckNetBIOS = $false` limits the package to LLMNR.
