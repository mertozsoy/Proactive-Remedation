# Disable Built-in Accounts

Enabled Guest accounts can remain unnoticed after device provisioning. These scripts find the account by SID, disable it and verify the result. DefaultAccount and WDAGUtilityAccount are observed but require explicit opt-in before they can be disabled.

## Files

| File | Purpose |
|---|---|
| `Detect-BuiltinAccounts.ps1` | Checks enabled local accounts with RID 501 and optional RIDs 503 and 504. Reports counts and RIDs without account names. |
| `Remediate-BuiltinAccounts.ps1` | Disables selected accounts with `Disable-LocalUser -SID` and verifies each account and the final state. |

## Deployment (Intune)

1. Review local GPO, Intune and other account management assignments. Exclude policy-owned accounts from this deployment or set `$AccountsManagedByPolicy = $true` in both scripts.
2. Go to **Devices > Scripts and remediations > Remediations > Create**.
3. Upload the detection and remediation scripts. Keep their configuration variables identical.
4. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No** for unsigned scripts. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a Windows client pilot group first. Schedule daily and review the output before widening the assignment.

## Notes

- Guest (RID 501) is disabled by default. Set `$DisableDefaultAccount` or `$DisableWdagUtilityAccount` to `$true` only after confirming the corresponding Windows feature does not need the account; both default to `$false`.
- Administrator (RID 500), WSIAccount and custom accounts are never targeted. No accounts, profiles or files are deleted; existing sessions are not ended.
- Domain-joined clients and declared policy-owned accounts are report-only when drift exists. Policy ownership is not fully discoverable; review local GPO and other management tools before assignment.
- An MDM result that enables Guest, or an unreadable policy state, blocks changes. Policy settings are never rewritten. `Blocked` exits 1 and must be resolved at the policy source.
- `Healthy` covers selected accounts only; `ObservedOnly` counts enabled optional accounts left unchanged. Logs use `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT_BuiltinAccounts.log`.
