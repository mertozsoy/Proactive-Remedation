# Disable Workplace Join

Users on hybrid joined devices can still add a personal work account from Settings. That creates an Entra registered state next to the existing hybrid joined state and makes SSO and Conditional Access results inconsistent. This pair writes the BlockAADWorkplaceJoin policy value and verifies it.

## Files

| File | Purpose |
|---|---|
| `Detect-WorkplaceJoin.ps1` | Reads `BlockAADWorkplaceJoin` under `HKLM\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin`. Exits 1 when the value is missing or not 1. |
| `Remediate-WorkplaceJoin.ps1` | Exports the policy key, creates it when missing, writes the value as DWORD 1 and re-reads it. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-WorkplaceJoin.ps1` as the detection script and `Remediate-WorkplaceJoin.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, then widen the scope.

## Notes

- The script blocks new workplace join attempts. It does not remove an existing Entra registered account from a user profile.
- Scope the pair to corporate devices. Users who need to add a work account on a personal device will lose that option.
- The previous state of the policy key is exported to `%ProgramData%\IntuneRemediations\Backup\WorkplaceJoin`.
- No service restart and no reboot. The value is read on the next join attempt.
- If GPO or another tool writes the same value, that source decides the final state. The output shows the value that was read after the write.
