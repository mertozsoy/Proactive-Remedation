# Remove TargetReleaseVersion Pin

Intune Remediations script pair. A `TargetReleaseVersion` pin written by an old GPO, a local policy or a previous RMM tool keeps the device on an old Windows version, and the Intune feature update policy never gets a chance. This pair finds the leftover pin and removes it.

## Files

| File | Purpose |
|---|---|
| `Detect-TargetReleaseVersionPin.ps1` | Reads `TargetReleaseVersion`, `TargetReleaseVersionInfo` and `ProductVersion` under `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate`. Flags an active pin that is not delivered by MDM and not listed in `$AllowedTargetVersions`. |
| `Remediate-TargetReleaseVersionPin.ps1` | Removes the three values, restarts `wuauserv` if it is running and verifies the key. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-TargetReleaseVersionPin.ps1` as the detection script and `Remediate-TargetReleaseVersionPin.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- If `TargetReleaseVersion` or `ProductVersion` exists under `PolicyManager\current\device\Update`, the pin comes from an MDM policy. The device is reported as `PolicyManaged` and nothing is changed.
- Put the versions you pin on purpose in `$AllowedTargetVersions`, for example `@('24H2')`. Use the same list in both scripts.
- A pin that still comes from a domain GPO returns on the next Group Policy refresh. Remove the GPO first.
- The script does not start an update scan. Windows Update picks up the change on its next scan.
