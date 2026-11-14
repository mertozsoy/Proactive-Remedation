# Update Microsoft 365 Apps Minimum Build

A security advisory usually names a fixed Office build. Devices that stay on an older build keep the vulnerability even when an update profile is assigned. These scripts read the Click-to-Run inventory, compare the installed build with an approved minimum and request an in-place update to that build.

## Files

| File | Purpose |
|---|---|
| `Detect-M365AppsMinimumBuild.ps1` | Reads the installed build and reports drift against `$MinimumBuild`. |
| `Remediate-M365AppsMinimumBuild.ps1` | Starts Click-to-Run, requests an update to `$MinimumBuild` and verifies the installed build afterwards. |

## Deployment (Intune)

1. Set `$MinimumBuild` to the build named in the advisory. Use the same value in both scripts.
2. Go to **Devices > Scripts and remediations > Remediations > Create**.
3. Upload the detection and remediation scripts.
4. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot device group and schedule outside working hours.

## Notes

- The requested build must be published on the channel the device uses. A build from another channel fails and the device stays pending.
- Open Office apps defer the update. Set `$CloseBlockingApps = $true` only where closing Office without saving is acceptable.
- Devices with an Office policy target below the minimum or a ConfigMgr client are skipped. Correct the managed source instead.
- `$VerifyTimeoutSeconds` controls how long the script waits for the inventory to show the new build. Nothing is restarted.
- A servicing profile can deploy a newer build first. The script enforces a floor only.
