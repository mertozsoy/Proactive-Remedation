# Repair LAPS Account

Intune Remediations script pair. Windows LAPS cannot rotate or back up a password when the account named in the policy is missing, disabled or not a local administrator. This pair reads the active LAPS policy, checks the target account and brings it back to a usable state.

## Files

| File | Purpose |
|---|---|
| `Detect-LapsAccount.ps1` | Reads the LAPS policy from the CSP or GPO registry key. Checks that the account in `AdministratorAccountName` exists, is enabled and is a member of the local Administrators group (resolved by SID `S-1-5-32-544`, so it works on any Windows language). |
| `Remediate-LapsAccount.ps1` | Creates the account with a random 32 character password, enables it, adds it to Administrators and calls `Invoke-LapsPolicyProcessing` so LAPS rotates the password right away. Verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-LapsAccount.ps1` as the detection script and `Remediate-LapsAccount.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- The account name is never hard coded. It comes from the LAPS policy on the device.
- Devices without a LAPS policy, or with automatic account management turned on (Windows 11 24H2), return `NotApplicable`.
- If the policy has no account name, LAPS manages the built-in Administrator. The scripts only enable it when `$EnableBuiltInAdmin` is `$true`. Default is `$false`.
- The random password is never written to the output or the log. LAPS replaces it during policy processing.
