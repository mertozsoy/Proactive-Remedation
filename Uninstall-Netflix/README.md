# Uninstall Netflix (Microsoft Store)

Intune Proactive Remediation script pair that detects and removes the **Netflix** Microsoft Store app (package family `4DF9E0F8.Netflix_mcm4njqhnhss8`) for all users on a device.

## Files

| File | Purpose |
|---|---|
| `Detect-Netflix.ps1` | Checks `Get-AppxPackage -AllUsers` for the Netflix package family. Exits `1` if found, `0` if not found. |
| `Remediate-Netflix.ps1` | Stops any running Netflix process, removes the Appx package for all users, removes the provisioned package, then verifies removal. Exits `1` if still present, `0` on success. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context**.
4. Assign to the target device group.

## Notes

- No environment-specific values are present in these scripts.
