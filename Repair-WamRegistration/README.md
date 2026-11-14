# Repair WAM Registration

Missing or unhealthy per-user AAD BrokerPlugin and CloudExperienceHost registrations can break Windows account dialogs and Microsoft 365 sign-in. These scripts check both components and re-register affected components from existing Windows manifests.

## Files

| File | Purpose |
|---|---|
| Detect-WamRegistration.ps1 | Checks current-user registration, AppX status and system manifests. |
| Remediate-WamRegistration.ps1 | Re-registers affected components and verifies registration health. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload Detect-WamRegistration.ps1 and Remediate-WamRegistration.ps1 in their respective fields.
3. Run this script using the logged-on credentials: **Yes**.
4. Enforce script signature check: **No** unless signed with a trusted certificate. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot user group. Schedule daily for registration drift or run on demand for a confirmed incident.

## Notes

- Requires Windows 10 version 1703 or later, or Windows 11, in the affected user's session.
- For confirmed symptoms with healthy registrations, set `$ForceReregister = $true` in both scripts temporarily. Restore `$false` after repair to stop repeated detection and registration.
- Missing source manifests, ambiguous registrations and unexpected families need manual Windows repair; nothing is downloaded.
- No token deletion, profile reset, policy override or forced application shutdown. In-use or policy-blocked registration fails; review AppXDeployment-Server events before retrying.
- Healthy registration does not prove sign-in or Start works. Test both with the user; CloudExperienceHost covers personal-account authentication and is not a replacement for Start menu repair.
