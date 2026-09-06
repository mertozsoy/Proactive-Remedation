# Uninstall TouchVPN (Microsoft Store)

Intune Proactive Remediation script pair that detects and removes the **TouchVPN** Microsoft Store app (package family `6F71D7A7.TouchVPN_nsbqstbb9qxb6`) for all users on a device.

## Files

| File | Purpose |
|---|---|
| `Detect-TouchVPN.ps1` | Checks `Get-AppxPackage -AllUsers` for the TouchVPN package family. Exits `1` if found, `0` if not found. |
| `Remediate-TouchVPN.ps1` | Stops any running TouchVPN process, removes the Appx package for all users, removes the provisioned package, then verifies removal. Exits `1` if still present, `0` on success. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context**.
4. Assign to the target device group.

## Notes

- No environment-specific values are present in these scripts.
- Useful for enforcing corporate VPN policy by blocking unmanaged consumer VPN apps.
