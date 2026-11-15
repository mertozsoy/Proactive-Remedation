# Remediate Teams Firewall Prompt

Intune Remediations script pair for shared and meeting room PCs. On these devices a new user can get the Windows Firewall popup on the first Teams call because no inbound allow rule exists for the Teams executable. This pair adds a machine wide allow rule for every Teams executable on the device and removes Query User block rules that point to Teams.

## Files

| File | Purpose |
|---|---|
| `Detect-TeamsFirewallPrompt.ps1` | Finds the Teams executables (classic per user, classic machine wide and new Teams) and checks whether an enabled inbound allow rule exists for each one. Also counts Query User block rules that point to Teams. Exits 1 if a rule is missing or a block rule is present. |
| `Remediate-TeamsFirewallPrompt.ps1` | Exports the local firewall policy, removes rules for Teams versions that are gone, removes Query User block rules for Teams and creates the missing inbound allow rules. Verifies the coverage before it exits. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-TeamsFirewallPrompt.ps1` as the detection script and `Remediate-TeamsFirewallPrompt.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily. Enforce signature check only if the scripts are signed.
5. Assign to the shared and meeting room device group. Start with a pilot group and check the output.

## Notes

- Medium impact: the script adds local inbound allow rules for the Teams programs. It does not open ports for other applications.
- `$RuleProfiles` defaults to `Any` so the rule also applies when the device classifies the meeting room network as Public. Set it to `Domain,Private` if inbound Teams traffic must stay on the corporate networks only.
- The Query User popup stays enabled by default. Set `$DisableQueryUserPopup = $true` to turn the popup off for all applications on the device.
- New Teams keeps its executable in a versioned WindowsApps folder. The script adds a rule for the current version and removes rules for versions that no longer exist.
- When policy sets local firewall rules to No the detection script reports NotApplicable and the remediation does nothing.
