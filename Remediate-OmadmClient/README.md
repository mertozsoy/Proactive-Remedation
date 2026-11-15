# Remediate OMA-DM Client

omadmclient.exe runs the OMA-DM sync session that pulls policy, compliance and app assignments from Intune. A session normally ends in minutes. On some devices the process stays alive, several copies pile up and the next sync waits behind the old ones. These scripts find instances that have been running past the threshold and terminate them.

## Files

| File | Purpose |
|---|---|
| `Detect-OmadmClient.ps1` | Reads every omadmclient.exe process, measures its running time and reports instances older than `$StuckMinutes` (30 by default). |
| `Remediate-OmadmClient.ps1` | Terminates stuck instances, keeps a young active session, then checks that no stuck instance is left. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-OmadmClient.ps1` and `Remediate-OmadmClient.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Schedule: Daily.
5. Assign to a pilot group before widening the scope.

## Notes

- Medium impact: the next scheduled MDM sync starts the session again.
- The newest instance is kept when it is younger than the threshold, so an active sync or a fresh enrollment is not killed.
- Only the process is terminated. No service restart, no registry change and no scheduled task change.
- Set `$EnableRemediation = $false` for observation only.
- Raise `$StuckMinutes` if a full sync on a slow network can take longer than 30 minutes.
