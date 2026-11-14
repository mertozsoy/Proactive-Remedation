# Report Feature Update Readiness

Intune Remediations script pair. A feature update sits at Offer ready for weeks and nobody knows why. This pair shows the reason on the device: safeguard holds, appraiser blockers, how close the current version is to end of servicing, and whether the compatibility data is too old.

## Files

| File | Purpose |
|---|---|
| `Detect-FeatureUpdateReadiness.ps1` | Reads safeguard hold IDs and blocker flags from the appraiser keys and compares the current build with the Windows 11 servicing table. Exits `1` only when appraiser data is older than `$AppraiserMaxAgeDays` (7). Everything else is reported. |
| `Remediate-FeatureUpdateReadiness.ps1` | Runs the Microsoft Compatibility Appraiser task again so the device sends fresh data. Throttled to once every `$RefreshThrottleDays` (7) days. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-FeatureUpdateReadiness.ps1` as the detection script and `Remediate-FeatureUpdateReadiness.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Safeguard holds are set by Microsoft and cannot be removed by a script. The output gives you the ID so you can check it in the release health dashboard.
- Update `$ServicingTable` when new Windows versions are released.
- Log: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT-REM-004.log`
