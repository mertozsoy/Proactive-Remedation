# Remediate Dirty Volume

An NTFS volume keeps its dirty bit set when Windows or another tool marks the file system as needing a check. If autochk exclusions are in place or the device is rarely restarted, chkdsk never runs and the same file system errors keep breaking application and update installations. These scripts find dirty volumes and schedule a check at the next start.

## Files

| File | Purpose |
|---|---|
| `Detect-DirtyVolume.ps1` | Reads the dirty flag of every fixed NTFS volume through the volume control code. Exits 1 when at least one volume is dirty. |
| `Remediate-DirtyVolume.ps1` | Clears autochk exclusions with `chkntfs /d`, schedules a check with `chkntfs /c` for each dirty volume and verifies that the exclusion is gone. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-DirtyVolume.ps1` as the detection script and `Remediate-DirtyVolume.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Enforce script signature check: **No**, unless both scripts are signed with a trusted certificate.
5. Assign to a pilot device group first, check the output, then widen the scope. Daily is enough.

## Notes

- chkdsk runs at the next restart. The script never restarts the device or the Intune Management Extension service.
- `chkntfs /d` restores default autochk behaviour and removes all drive exclusions, including exclusions that were added on purpose for other volumes.
- `$ResetBootExclusions` and `$ScheduleBootCheck` can be set to `$false` to report the state without scheduling anything.
- The dirty bit stays set until chkdsk completes, so the output shows the count of volumes that are still waiting for the check.
- The log file is written to `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT_DirtyVolume.log`.
