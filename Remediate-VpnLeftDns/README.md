# Remediate VPN Left DNS

Intune Remediations script pair. Some VPN clients write their own DNS servers as a static value on the physical Wi-Fi or Ethernet adapter and do not put the adapter back on DHCP DNS when the tunnel closes. This pair finds that leftover static list and resets the adapter to the DHCP-provided DNS servers.

## Files

| File | Purpose |
|---|---|
| `Detect-VpnLeftDns.ps1` | Reads every physical adapter that uses DHCP and reports adapters whose static DNS list differs from the DHCP list. `$VpnAdapterPatterns` and `$ExcludeInterfaceAlias` limit the scope. |
| `Remediate-VpnLeftDns.ps1` | Exports the TCP/IP interface key, resets the DNS server list of each affected adapter, flushes the DNS cache and verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-VpnLeftDns.ps1` as the detection script and `Remediate-VpnLeftDns.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- The check is skipped while a non-physical VPN adapter is up, so an active tunnel is never changed.
- Only adapters with DHCP enabled and a DHCP-provided DNS list are reset. A device cannot lose its only DNS servers.
- Add adapters with intentional static DNS to `$ExcludeInterfaceAlias` before deployment.
- The TCP/IP interface key is exported to `%ProgramData%\IntuneRemediations\Backup` before each reset.
- The check reads IPv4. The reset command clears static DNS for both IPv4 and IPv6 on the adapter.
