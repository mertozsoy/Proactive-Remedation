# Remove Enrolling User Admin

Enrollment can leave an Entra user in local Administrators after the enrollment settings change. These scripts detect and optionally remove unapproved direct Entra user members without device-to-user mapping. They do not identify the enrolling or primary user.

## Files

| File | Purpose |
|---|---|
| `Detect-EnrollingUserAdmin.ps1` | Finds direct User members with S-1-12-1- SIDs outside `$AllowedSids` in group S-1-5-32-544. |
| `Remediate-EnrollingUserAdmin.ps1` | Removes matching members when enabled and an enabled local administrator remains, then verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Set `$AllowedSids` identically in both scripts for approved Entra user exceptions. An empty list exempts nobody.
3. Upload the detection and remediation files.
4. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
5. Assign to a pilot group with a daily schedule. Review results and recovery access before setting `$EnableRemediation = $true` in the remediation script.

## Notes

- `$EnableRemediation = $false` reports drift without removal and returns exit 1.
- All matching direct Entra users are in scope, not just the enrolling user. Groups, including Entra role groups, and local accounts are untouched.
- Removal requires an enabled local user directly in Administrators, checked by local account SID before each removal. Disabled accounts and group-based access do not qualify.
- Verify recovery credentials and LAPS password access separately; the guard does not test sign-in, password validity, or escrow.
- Align enrollment and Account Protection assignments first. A policy can restore membership. Existing session tokens can retain rights until the next sign-in; no forced sign-out occurs.
