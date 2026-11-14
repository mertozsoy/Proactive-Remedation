# Remediate WinRE

Intune Remediations script pair. When WinRE is disabled, Reset this PC, Fresh Start and some cumulative updates fail. This pair turns it back on.

## Files

| File | Purpose |
|---|---|
| `Detect-WinRE.ps1` | Reads InstallState from `ReAgent.xml`, with `reagentc /info` as a fallback. |
| `Remediate-WinRE.ps1` | Runs `reagentc /enable`. If it fails, it reports whether `Winre.wim` is missing. Partitions are never changed. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-WinRE.ps1` as the detection script and `Remediate-WinRE.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Weekly.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Resizing or recreating the recovery partition is left to the administrator.
