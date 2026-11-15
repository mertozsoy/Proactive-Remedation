# Repair AD Secure Channel

A hybrid workstation can lose its AD trust relationship while remaining managed by Intune. These scripts test the secure channel and attempt repair with the current SYSTEM identity, then verify the result.

## Files

| File | Purpose |
|---|---|
| `Detect-AdSecureChannel.ps1` | Checks domain membership, Netlogon and writable DC discovery, then tests the secure channel. |
| `Remediate-AdSecureChannel.ps1` | Rechecks the failure, rebuilds the channel with Test-ComputerSecureChannel -Repair and verifies it. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-AdSecureChannel.ps1` and `Remediate-AdSecureChannel.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** unless you sign both scripts.
4. Assign only to a pilot group of hybrid joined Windows workstations. Entra registration is not checked locally.
5. Schedule daily when corporate network or device VPN connectivity is available.

## Notes

- Repair is enabled by default. Set `$EnableRemediation = $false` to observe without repair.
- SYSTEM may lack AD permissions or usable machine credentials. Failed repairs require authorized AD assistance; no passwords are stored or requested.
- Keep `$DomainController` identical in both scripts; leave empty for automatic selection or specify a reachable writable DC.
- Deferred means a prerequisite failed, not proven broken trust. DC discovery alone does not prove RPC connectivity; all inconclusive checks exit 1.
- Domain controllers and servers are excluded. No restart, domain rejoin, Entra changes or policy changes are performed.
