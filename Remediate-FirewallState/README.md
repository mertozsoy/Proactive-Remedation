# Remediate Firewall State

Disabled Windows Defender Firewall profiles can cause Intune compliance failures. These scripts check all three effective profile states and MpsSvc, enable local profiles and restore the service when stopped or disabled. Confirmed stale policy values can be removed on non-domain devices with an explicit opt-in.

## Files

| File | Purpose |
|---|---|
| `Detect-FirewallState.ps1` | Checks Domain, Private and Public profiles in ActiveStore, EnableFirewall policy values and MpsSvc. Exits 1 for drift or an error. |
| `Remediate-FirewallState.ps1` | Restores MpsSvc and enables disabled local profiles in PersistentStore. Optionally backs up and removes stale EnableFirewall=0 values, then verifies ActiveStore. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-FirewallState.ps1` as detection and `Remediate-FirewallState.ps1` as remediation.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
4. Schedule: Daily.
5. Assign to a pilot group first and verify application connectivity before widening the scope.

## Notes

- `$RemoveLocalPolicyValue = $false` preserves policy values. Enable it only after confirming the disabling policy is retired and no active GPO or MDM policy manages it.
- Domain-joined devices always preserve policy values, even with cleanup enabled. Correct active policy at its management source.
- Optional cleanup exports the affected profile key to `%ProgramData%\IntuneRemediations\Backup` before removing only EnableFirewall=0. Registry.pol and other firewall rules remain unchanged.
- `Off(Policy)` identifies a disabling registry value, not its owner. `Off(Unspecified)` does not prove local ownership. Unresolved effective settings return exit 1.
- Logs: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT_FirewallState.log`. No restart is requested; this checks profile enablement, not full firewall rule compliance.
