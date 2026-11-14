# Report Network PST Files

Detection only script for Intune Remediations. Outlook PST files stored on a network share are an unsupported configuration. Every write goes over SMB while Outlook keeps the file open, so the profile slows down and the file can be corrupted when the link drops. This script scans the share roots you define and the mapped drives of the signed-in user, then reports where PST files still live.

## Files

| File | Purpose |
|---|---|
| `Detect-NetworkPstFiles.ps1` | Scans each UNC root from `$ShareRoots` plus the mapped network drives for `.pst` files. Reads folder depth up to `$MaxDepth` and stops after `$MaxFolders`. Reports count, total size, largest file and stale files. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-NetworkPstFiles.ps1` as the detection script. Leave the remediation script empty.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Weekly.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Report only. No PST file is moved, renamed or deleted.
- Fill `$ShareRoots` with the share roots to scan, for example `\\fs01\Users`. With an empty list the script only scans the mapped drives of the user.
- A server that does not answer on TCP 445 is skipped and counted in `Offline`. Scanning a very large share can take several minutes, lower `$MaxDepth` or `$MaxFolders` if needed.
- Set `$ShowFullPaths = $true` to print UNC paths in the output. By default only file names are printed and the full paths go to the log file.
- Outlook itself is not touched, so files currently open stay locked and are still reported with their last write time.
