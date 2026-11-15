# Report Work Accounts

Detection only script for Intune Remediations. A device can carry more than one work account: an old Entra ID profile from a previous user, an Office identity from another tenant or an enrollment record that was never cleaned up. Licensing and SSO then pick the wrong identity. This script lists the work accounts it can see on the device and flags the domains that are not on your allowed list.

## Files

| File | Purpose |
|---|---|
| `Detect-WorkAccounts.ps1` | Collects work accounts from Entra ID user profiles (SIDs that start with S-1-12-1), Office identities of the signed-in user and MDM enrollment records. Compares the domains with `$AllowedDomains` and the count with `$MaxWorkAccounts`. Output keeps domains and counts only; account names go to the log file. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-WorkAccounts.ps1` as the detection script. Leave the remediation script empty.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Weekly.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Report only. No account is disconnected, no profile and no enrollment record is removed.
- Fill `$AllowedDomains` with your tenant domains, for example `contoso.com`. With an empty list only the count limit is checked. Set `$MaxWorkAccounts` to `0` to disable the count check.
- The Office identity key under `HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Identity\Identities` and the value names under `HKLM:\SOFTWARE\Microsoft\Enrollments` are not documented by Microsoft as a public contract. The script scans for value names that contain a mail address instead of hard coding them, and a missing or unreadable key only zeroes that source.
- A standard user may not be able to read the enrollment key. The script logs a warning and keeps the other two sources.
- To remove an account use **Settings > Accounts > Access work or school** and disconnect it.
