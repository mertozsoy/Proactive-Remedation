# Remove Duplicate Profile Entries

Duplicate ProfileList paths and SID backup entries can indicate profile migration problems. Detection flags these entries. Remediation removes explicitly approved duplicates after exporting ProfileList and checking that an unloaded local profile entry will remain.

## Files

| File | Purpose |
|---|---|
| `Detect-DuplicateProfileEntries.ps1` | Flags user SID backup keys and shared ProfileImagePath values without exposing identities. |
| `Remediate-DuplicateProfileEntries.ps1` | Backs up ProfileList, removes approved duplicate keys and verifies the retained entry and remaining findings. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Select `Detect-DuplicateProfileEntries.ps1` and `Remediate-DuplicateProfileEntries.ps1`.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Assign to a small pilot group. Start with a daily schedule and review findings against Windows Setup logs.
5. After confirming the invalid key, populate `$ApprovedRepairs` with `@{ RemoveKey = $InvalidKeyName; KeepKey = $RetainedKeyName }` using actual key names as strings. Set `$EnableRemediation = $true` only for the reviewed devices and use a maintenance window with affected users signed out.

## Notes

- Default: `$EnableRemediation = $false` and no approved repairs. Unresolved findings return exit 1, including when changes are disabled.
- A .bak suffix alone does not prove a stale entry. Different paths, lone backup keys and unapproved duplicates require manual review; no automatic rename or State reset is attempted.
- Only same-path duplicates with a retained plain SID entry and an existing NTUSER.DAT qualify. Loaded, special, roaming, unhealthy and reparse-point profiles are protected.
- No profile files are deleted. Registry exports are saved under `%ProgramData%\IntuneRemediations\Backup`; protect them as sensitive data and use the matching export for an administrator-reviewed restore if needed.
- Findings do not prove an upgrade or reset blocker. Confirm the invalid entry in Setup logs and account ownership first; coordinate with profile management and do not target policy-maintained entries.
