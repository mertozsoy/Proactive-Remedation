# Disable RDP Access

Remote Desktop is often left enabled on clients that never needed it. These scripts report clients that accept RDP without approval and close the listener and the port 3389 firewall rules on those clients.

## Files

| File | Purpose |
|---|---|
| `Detect-RdpAccess.ps1` | Reads `fDenyTSConnections` and lists every enabled inbound firewall rule that opens TCP or UDP port 3389. Reports drift, a policy block or an approved device. |
| `Remediate-RdpAccess.ps1` | Sets `fDenyTSConnections` to 1, disables those firewall rules and verifies both again. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-RdpAccess.ps1` as the detection script and `Remediate-RdpAccess.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Assign to all clients and exclude the approved RDP group from the assignment.
5. Start with a pilot group, check the output, then widen the scope.

## Notes

- Assignment exclusion is the main control for approval. As a second guard the script accepts a client when the local group `RDP-Approved` exists and has at least one member, or when the computer name is listed in `$ApprovedDeviceNames`.
- Medium impact: new RDP connections are refused after the change. Existing sessions are not disconnected and the device is not restarted.
- An RDP setting delivered by policy is reported as `Blocked` with exit 1. The script does not overwrite policy values. Remove the client from that assignment or fix the policy.
- Set `$EnableRemediation = $false` for a report-only pass. Set `$DisableFirewallRules = $false` to keep the firewall rules and only close the listener.
- Output and log contain no user or device names. The log is written to `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT_RdpAccess.log`.
