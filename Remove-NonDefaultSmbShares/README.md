# Remove Non-Default SMB Shares

Intune Remediations script pair. Users share folders on their own workstation, often with Everyone full access, and those shares stay behind long after the folder is no longer needed. This pair lists every SMB share that is not a built-in administrative share and removes the ones that are not on your allow list.

## Files

| File | Purpose |
|---|---|
| `Detect-NonDefaultSmbShares.ps1` | Lists SMB shares that are not built-in administrative shares. Skips names in `$AllowedShareNames`. Resolves each share ACL to SIDs and flags shares that allow Everyone or Authenticated Users. |
| `Remediate-NonDefaultSmbShares.ps1` | Exports the LanmanServer share key, writes a JSON copy of each share definition and ACL, then removes the share with `Remove-SmbShare`. Shares with open files are skipped unless `$RemoveWithOpenFiles` is set. Verifies that no custom share is left. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-NonDefaultSmbShares.ps1` as the detection script and `Remediate-NonDefaultSmbShares.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Removing a share stops the sharing only. Files on disk are left in place.
- Shares with open files are skipped by default. `Remove-SmbShare` disconnects clients and they can lose unsaved data.
- Backups go to `%ProgramData%\IntuneRemediations\Backup\NonDefaultSmbShares`.
- `$RemoveShares = $false` by default: the pair only reports. Scan-to-folder and app shares are common on office PCs. Fill `$AllowedShareNames` with the shares that must stay, then enable removal.
- Requires the SmbShare module. The script exits 0 as NotApplicable when it is missing.
