# Set Device Primary User Admin

Some users need local admin rights on their own device only. Account Protection cannot target a single device per user. This script pair maps each device to its approved user by computer name or BIOS serial number and adds that user to Administrators only when the profile exists on the device.

## Files

| File | Purpose |
|---|---|
| `Detect-DevicePrimaryUserAdmin.ps1` | Resolves the mapped account and its profile, then checks direct membership in Administrators (S-1-5-32-544). Exits 1 when the mapped user is missing. |
| `Remediate-DevicePrimaryUserAdmin.ps1` | Adds the mapped user with a profile to Administrators when enabled, then verifies membership. |

## Deployment (Intune)

1. Fill `$ApprovedDeviceUsers` in both scripts with the same device to user mapping.
2. Go to **Devices > Scripts and remediations > Remediations > Create**.
3. Upload the detection and remediation files.
4. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
5. Assign to a pilot group with a daily schedule. Set `$EnableRemediation = $true` after the report-only output looks correct.

## Notes

- Keys can be the computer name or the BIOS serial number. Values accept `AzureAD\UPN` or `DOMAIN\user`.
- An empty or unmatched mapping returns NotApplicable and changes nothing.
- `$EnableRemediation = $false` reports drift and exits 1.
- Only direct membership is added. No member is removed from any group.
- A policy or Account Protection assignment can override the result. No sign-out or restart is forced.
