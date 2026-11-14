# Remove Unapproved Local Accounts

Local accounts created during setup, testing or by users often stay on devices for years. These scripts compare every local account with an approved list, then disable or delete the ones that are not on it.

## Files

| File | Purpose |
|---|---|
| `Detect-UnapprovedLocalAccounts.ps1` | Lists local accounts outside the approved list and exits 1 when one of them is enabled. |
| `Remediate-UnapprovedLocalAccounts.ps1` | Disables the unapproved accounts and deletes them when deletion is approved. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-UnapprovedLocalAccounts.ps1` and `Remediate-UnapprovedLocalAccounts.ps1`.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Fill `$ApprovedAccounts` in both scripts with the accounts that must stay. An empty list returns NotApplicable.
5. Assign to a pilot group first and keep the default daily schedule.

## Notes

- Built-in accounts are skipped by relative identifier below 1000. Domain and Microsoft account sources are never touched.
- `$DeleteUnapprovedAccounts = $false` keeps the account and only disables it. Set it to `$true` to remove the account and its profile.
- Accounts with a loaded profile are skipped. Deletion is blocked when the account is the last local administrator.
- `$MaxAccountsPerRun` limits how many accounts one run handles. Remaining accounts are handled on the next run.
- Profile registry keys are backed up to `%ProgramData%\IntuneRemediations\Backup`. The backup does not restore profile files.
