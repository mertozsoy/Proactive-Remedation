# Repair AOVPN Device Tunnel

A missing Always On VPN device tunnel profile can prevent access to domain resources before sign-in. These scripts detect the missing profile and recreate it from your approved ProfileXML through the Windows WMI bridge. Existing profiles are never replaced.

## Files

| File | Purpose |
|---|---|
| `Detect-AovpnDeviceTunnel.ps1` | Checks device VPN CSP records and all-user VPN connections for the expected device tunnel. |
| `Remediate-AovpnDeviceTunnel.ps1` | Creates a missing script-owned profile and verifies its presence in both views. |

## Deployment (Intune)

1. Set `$ProfileName` identically in both scripts. Set `$ProfileOwner` to `Script` only after confirming no Intune profile or GPO manages this tunnel; otherwise use `Policy`.
2. Set `$ApprovedProfileXml` in the remediation script to your tested raw VPNProfile XML using a single-quoted here-string. Include your VPN server, routes and any required DNS settings.
3. Go to **Devices > Manage devices > Scripts and remediations > Create script package**. Upload both scripts.
4. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot group of supported domain-joined Enterprise or Education clients. Schedule daily, then expand after reviewing results.

## Notes

- Configuration is required. A missing profile has no reliable local ownership evidence; confirm ownership before selecting `Script`.
- Device tunnels require IKEv2, machine certificate authentication and split tunneling. Provision a valid machine certificate and server trust first.
- Policy-owned missing profiles are reported only. Redeploy their authoritative policy instead of creating a competing profile.
- Existing or inconsistent profiles and another device tunnel block creation. Review them without deleting working connections.
- Verification proves profile presence, not certificate selection, VPN connection or DC reachability. No restart or forced connection occurs.
