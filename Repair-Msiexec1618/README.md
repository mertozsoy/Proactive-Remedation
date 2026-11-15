# Repair Msiexec 1618

A crashed or hung msiexec leaves the Windows Installer InProgress key behind. From then on every MSI install and uninstall fails with 1618 (0x80070652), and a reboot does not clear it. This pair finds that state, ends an installer process that has run past the threshold, removes the key after a backup and checks that the installer is free again.

## Files

| File | Purpose |
|---|---|
| `Detect-Msiexec1618.ps1` | Reads the `InProgress` key and lists `msiexec.exe` processes with an install command line. A process younger than `$HungProcessMinutes` counts as a live install. Exit 1 on a stale key with no process, or on a process older than the threshold. |
| `Remediate-Msiexec1618.ps1` | Ends the hung `msiexec` processes, waits for them to exit, exports the `InProgress` key to `%ProgramData%\IntuneRemediations\Backup`, removes the key and verifies both. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-Msiexec1618.ps1` as the detection script and `Remediate-Msiexec1618.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: every 4 hours, or daily if software installs are rare.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- A live installation younger than `$HungProcessMinutes` is left alone. Detection returns `Busy` and the remediation does nothing.
- Ending hung `msiexec` processes is off by default because it aborts that installation. Set `$TerminateHungMsiexec = $true` after a pilot test.
- The key is exported to `%ProgramData%\IntuneRemediations\Backup` before removal. A failed export stops the cleanup.
- Set `$RemoveStaleInProgressKey = $false` to leave the key in place and only report it.
- A pending reboot can also return 1618. This script does not clear `PendingFileRenameOperations`.
