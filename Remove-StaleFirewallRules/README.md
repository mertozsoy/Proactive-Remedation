# Remove Stale Firewall Rules

Local firewall rules pile up on managed devices. Users allow an app through the firewall prompt and the rule stays after the app is removed. Orphaned rules point to a program or service that no longer exists and nobody removes them. This pair lists local allow rules that are orphaned or created by users, and removes them after exporting the local rule set.

## Files

| File | Purpose |
|---|---|
| `Detect-StaleFirewallRules.ps1` | Reads local allow rules from the persistent store and reports rules whose program or service is missing. Also reports inbound allow rules that point to a program under a user writable folder. `$KeepRuleNames` and `$KeepProgramPaths` keep known good rules. |
| `Remediate-StaleFirewallRules.ps1` | Exports the local firewall rules with `reg export` and removes the reported rules from the persistent store. Orphaned rules are removed by default, user app rules only when `$RemoveUserCreatedRules` is set to `$true`. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-StaleFirewallRules.ps1` as the detection script and `Remediate-StaleFirewallRules.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Only rules in the local persistent store are read and removed. Rules delivered by GPO or Intune firewall policy live in other stores and are never touched.
- Orphaned rules are removed by default. User created rules are only reported until `$RemoveUserCreatedRules` is set to `$true`. Start in report mode first.
- The local rule set is exported to `%ProgramData%\IntuneRemediations\Backup` before the first removal.
- Removing a user app rule can bring the firewall prompt back for that app. Add wanted rules to `$KeepRuleNames` or their programs to `$KeepProgramPaths`.
- Medium impact: a program that installs its rule again on every start keeps the device in drift. Use the output to find those programs.
