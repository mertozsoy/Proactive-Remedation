# Enable Explorer Thumbnails

File Explorer shows icons only when the per-user thumbnail setting is off or when a thumbnail policy is applied. The setting is easy to turn off by accident and is often written back by a leftover policy. This pair turns thumbnails back on for the signed-in user and reports the cases a policy controls.

## Files

| File | Purpose |
|---|---|
| `Detect-ExplorerThumbnails.ps1` | Reads `IconsOnly` under the user Explorer key and `DisableThumbnails` under the user policy key. |
| `Remediate-ExplorerThumbnails.ps1` | Sets `IconsOnly` to 0, optionally removes a tattooed user policy value with a registry backup, then verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-ExplorerThumbnails.ps1` and `Remediate-ExplorerThumbnails.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **Yes**.
4. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot group first. Schedule daily.

## Notes

- `IconsOnly = 1` means icons only. A missing value or 0 means thumbnails are on.
- `DisableThumbnails` under the user policy key wins over the user setting. It is reported and never changed unless `FixUserPolicy` is enabled.
- `FixUserPolicy` is off by default. When enabled, the user policy value is exported to a backup file before it is removed.
- `ClearThumbnailCache` and `RestartExplorer` are off by default. Both are only needed when thumbnails stay blank after the setting is corrected.
- A GPO or an Intune policy that writes the value must be corrected at the source. The script reports `PolicyBlocked` and exits 1 in that case.
