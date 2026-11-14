# Repair Start Menu Registration

A broken per-user shell registration can prevent the Start menu from opening. These scripts check StartMenuExperienceHost and ShellExperienceHost and re-register affected components from their existing Windows manifests.

## Files

| File | Purpose |
|---|---|
| Detect-StartMenuRegistration.ps1 | Checks current-user registration, AppX status and available system manifests. |
| Remediate-StartMenuRegistration.ps1 | Re-registers affected components and verifies their registration status. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload Detect-StartMenuRegistration.ps1 and Remediate-StartMenuRegistration.ps1 in their respective fields.
3. Run this script using the logged-on credentials: **Yes**.
4. Enforce script signature check: **No** unless signed with a trusted certificate. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot user group. Use a daily schedule for registration drift or an on-demand run for confirmed incidents.

## Notes

- Requires Windows 10 version 1903 or later, or Windows 11, in the affected user's non-elevated session.
- For a confirmed fault with healthy registrations, set `$ForceReregister = $true` in both scripts. Restore `$false` after the incident to avoid repeated repairs and persistent detection failures.
- Registration status does not prove that Start opens. Confirm the result with the affected user.
- Missing or ambiguous system manifests require manual Windows repair. No downloads, profile resets or policy changes are attempted.
- Applications are not forcibly closed. In-use or policy-blocked registration returns failure; review the AppX deployment logs before retrying.
