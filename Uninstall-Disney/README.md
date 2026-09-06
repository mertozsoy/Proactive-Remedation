# Uninstall Disney+ (Microsoft Store)

Intune Proactive Remediation script pair that detects and removes the **Disney+** Microsoft Store app (package family `Disney.37853FC22B2CE_6rarf9sa4v8jt`) for all users on a device.

## Files

| File | Purpose |
|---|---|
| `Detect-Disney.ps1` | Checks `Get-AppxPackage -AllUsers` for the Disney package family. Exits `1` if found, `0` if not found. |
| `Remediate-Disney.ps1` | Stops any running Disney process, removes the Appx package for all users, removes the provisioned package (so it isn't reinstalled for new user profiles), then verifies removal. Exits `1` if still present, `0` on success. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context** (required for `-AllUsers` Appx operations and provisioned package removal).
4. Assign to the target device group.

## Notes

- No environment-specific values are present in these scripts.
- Package family names are Store-specific identifiers, not sensitive data — safe to reuse as-is.
