# Uninstall Microsoft Teams Personal (Microsoft Store)

Intune Proactive Remediation script pair that detects and removes the **consumer/personal Microsoft Teams** MSIX app (package family `MicrosoftTeams_8wekyb3d8bbwe`) for all users on a device.

## Files

| File | Purpose |
|---|---|
| `Detect-MicrosoftTeamsPersonal.ps1` | Checks `Get-AppxPackage -AllUsers` for the Teams Personal package family. Exits `1` if found, `0` if not found. Logs to `C:\Temp\TeamsPersonal_Detect.log`. |
| `Remediate-MicrosoftTeamsPersonal.ps1` | Stops running Teams processes, removes the Appx package for all users, removes the provisioned package, then verifies removal. Logs to `C:\Temp\TeamsPersonal_Remediate.log`. |

## ⚠️ Important warning

The package family `MicrosoftTeams_8wekyb3d8bbwe` is also used by the **new Microsoft Teams (work or school)** machine-wide installer in some configurations. **Verify on a test device** that this only targets the personal/consumer Teams app before deploying broadly, especially if your organization uses the new Teams client.

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context**.
4. Pilot on a small test group first given the package family overlap noted above.

## Notes

- No environment-specific values are present in these scripts.
