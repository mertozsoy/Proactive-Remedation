# Remove DefaultUserZero

The defaultuser0 local account or profile can remain after provisioning. These scripts detect the leftovers and remove the verified profile and account when destructive cleanup is approved.

## Files

| File | Purpose |
|---|---|
| `Detect-DefaultUserZero.ps1` | Checks the exact account, registered profile and expected folder. |
| `Remediate-DefaultUserZero.ps1` | Backs up the profile registry entry, removes the unloaded profile through CIM, deletes the account by SID and verifies removal. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-DefaultUserZero.ps1` and `Remediate-DefaultUserZero.ps1`.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Assign only to devices that completed Autopilot and ESP. Start with a pilot group and a daily schedule.
5. Review the target data and set `$EnableRemediation = $true` to approve account and profile deletion.

## Notes

- `$EnableRemediation = $false` prevents deletion and returns exit 1 while leftovers remain.
- Keep `$ExpectedProfilePath` identical in both scripts. Only defaultuser0 is targeted; suffixed folders are outside scope.
- Loaded, special, mismatched or redirected profiles are blocked. Cleanup also requires another user profile and completed Windows setup.
- Unregistered folders require manual review. No raw folder deletion, policy changes, restart or sign-out is performed.
- Registry backups use `%ProgramData%\IntuneRemediations\Backup`. They do not restore deleted files or the account; preserve needed data separately.
