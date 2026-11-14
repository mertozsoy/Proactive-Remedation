# Repair FortiClient VPN Tunnel

FortiClient can remain installed after its corporate SSL VPN tunnel settings disappear. These scripts restore a basic standalone FortiClient VPN 7.x profile and verify its registry values without replacing existing settings.

## Files

| File | Purpose |
|---|---|
| `Detect-FortiClientVpnTunnel.ps1` | Checks the named tunnel and four expected values. Missing or conflicting settings return exit 1. |
| `Remediate-FortiClientVpnTunnel.ps1` | Creates the missing tunnel or adds missing values, then verifies the result. Conflicting values are left unchanged. |

## Deployment (Intune)

1. Set `$TunnelName`, `$VpnServer`, `$TunnelDescription` and the installed `$ClientExecutable` path identically in both scripts. Use your approved gateway, optionally with its port.
2. Confirm that the target group uses standalone FortiClient VPN 7.x with no EMS, GPO or other configuration owner. Set `$StandaloneDeploymentConfirmed = $true` in both scripts only for that group.
3. Go to **Devices > Scripts and remediations > Remediations > Create**. Upload the detection and remediation scripts.
4. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot device group and schedule daily. Verify the tunnel in FortiClient and test a connection before expanding.

## Notes

- Basic SSL VPN only: username prompt enabled and client certificate prompt disabled. IPsec, SAML and certificate-based profiles need their own approved configuration.
- Scope confirmation defaults to false; EMS/GPO ownership is not inferred from undocumented registry flags. Managed devices must use their configuration owner.
- Existing value conflicts are reported without changes. No keys, credentials or other tunnels are deleted or overwritten.
- Fortinet documents tunnel registry deployment for unmanaged 7.x clients; other major versions are skipped.
- No connection is started or stopped. Registry verification does not prove authentication or connectivity; reopen the VPN window if needed.
