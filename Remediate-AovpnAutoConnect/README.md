# Remediate AOVPN Auto Connect

Intune Remediations script pair. Windows writes the name of an Always On VPN profile to `AutoTriggerDisabledProfilesList` when a user clears the Connect automatically checkbox. The checkbox can stay off and greyed out after that. This pair finds the profile names in that list and removes them so the Always On trigger works again.

## Files

| File | Purpose |
|---|---|
| `Detect-AovpnAutoConnect.ps1` | Reads `AutoTriggerDisabledProfilesList` under the RasMan Config key and lists the profile names that block auto-connect. `$ProfileNames` limits the check to given profiles. |
| `Remediate-AovpnAutoConnect.ps1` | Exports the RasMan Config key, removes the profile names from the value and verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-AovpnAutoConnect.ps1` as the detection script and `Remediate-AovpnAutoConnect.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- The value exists to keep a user's manual choice. Removing a name also removes that choice. Start with a pilot group.
- The RasMan Config key is exported to `%ProgramData%\IntuneRemediations\Backup` before the value changes.
- Set `$ProfileNames` to limit the cleanup to specific profiles. An empty list means every entry is removed.
- No tunnel is dropped and no service is restarted. The change applies on the next trigger or sign-in.
- If a user clears the checkbox again, Windows writes the profile name back and the next run removes it again.
