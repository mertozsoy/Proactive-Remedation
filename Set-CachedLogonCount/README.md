# Set Cached Logon Count

Windows caches the credentials of the last domain users that signed in, so they can log on while a domain controller is unreachable. The default is 10 cached logons. On shared or long-lived devices that means a former employee can still sign in offline with an old password. These scripts read `CachedLogonsCount` under Winlogon and lower it to a maximum of 4.

## Files

| File | Purpose |
|---|---|
| `Detect-CachedLogonCount.ps1` | Reads `CachedLogonsCount` and exits 1 when the value is missing, not numeric, outside 0 to 50, or above `$MaxCachedLogons`. |
| `Remediate-CachedLogonCount.ps1` | Exports the Winlogon key to a backup file, writes the maximum as a string value and reads it back. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-CachedLogonCount.ps1` and `Remediate-CachedLogonCount.ps1`.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Enforce script signature check: **No**, unless both scripts are signed with a trusted certificate.
5. Assign to a pilot group and schedule daily. Check results before widening the assignment.

## Notes

- Set `$MaxCachedLogons` in both scripts to the same value. Microsoft documents a range of 0 to 50, where 0 turns caching off.
- A value of 2 or 3 covers laptop users who work offline for a day. Keep some cache on mobile devices or those users cannot sign in without a domain controller.
- Cached credentials of users who already signed in stay until they are replaced by newer logons. The lower count applies to new caching, not to existing entries.
- If a security baseline or GPO also sets this value, the policy wins on its next refresh. Exclude those devices or change the source policy instead.
- The backup file is written to `%ProgramData%\IntuneRemediations\Backup` before the value is changed.
