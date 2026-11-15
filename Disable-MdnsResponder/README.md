# Disable mDNS Responder Traffic

Disabling LLMNR does not block mDNS. These scripts check and enforce four Windows Firewall block rules for inbound and outbound UDP 5353 traffic using both local and remote ports.

## Files

| File | Purpose |
|---|---|
| `Detect-MdnsResponder.ps1` | Checks firewall prerequisites and the four effective block rules. |
| `Remediate-MdnsResponder.ps1` | Creates or repairs owned local rules and verifies the effective configuration. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Upload `Detect-MdnsResponder.ps1` and `Remediate-MdnsResponder.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **No**.
4. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot device group. Schedule daily after testing discovery-dependent applications.

## Notes

- Blocks network traffic for all programs and profiles over IPv4 and IPv6; does not stop responder processes or remove listeners. Verification checks configuration, not packets.
- Requires Windows Firewall running on all profiles with no excluded interfaces. Disabled local rule merging or rule ownership conflicts require central policy changes; scripts never override them.
- May disrupt Bonjour, printer discovery and Delivery Optimization local peer discovery. Standard DNS on port 53 is unchanged.
- Keep both scripts' settings identical. No undocumented mDNS registry switch is used.
- Rollback: stop the assignment and remove only the four rules named `IRT-MdnsResponder-Inbound-Local`, `IRT-MdnsResponder-Inbound-Remote`, `IRT-MdnsResponder-Outbound-Local` and `IRT-MdnsResponder-Outbound-Remote` from the local store.
