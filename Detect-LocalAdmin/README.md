# Detect Unauthorized Local Admins

Intune Proactive Remediation **detection-only** script that flags any local user account in the `Administrators` group that isn't on an explicit allow-list.

## Files

| File | Purpose |
|---|---|
| `Detect-LocalAdmin.ps1` | Enumerates members of the local `Administrators` group via `Get-LocalGroupMember`, filters to user accounts (skips groups), and compares each account name against an `$AllowedAdmins` allow-list. Exits `1` (non-compliant) and lists the unauthorized accounts if any are found, exits `0` (compliant) otherwise. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload `Detect-LocalAdmin.ps1` as the detection script.
3. **Edit `$AllowedAdmins`** to match your organization's actual approved local admin account names (the sample values `demo.admin`, `demo.user1`, `demo.user2` are placeholders and must be replaced before use).
4. Run in the **system context**.
5. This script is detection-only — pair it with your own remediation script (e.g. one that removes unauthorized accounts from the group) if you want automatic remediation rather than reporting-only.

## Notes

- The account names in `$AllowedAdmins` are demo placeholders, not real usernames — replace them with your environment's actual approved admin accounts before deploying.
