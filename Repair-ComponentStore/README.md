# Repair Component Store

Windows component store corruption can prevent updates and optional features from installing. These scripts scan with DISM, repair a repairable image and verify the result with a full scan.

## Files

| File | Purpose |
|---|---|
| `Detect-ComponentStore.ps1` | Runs ScanHealth and reports healthy, repairable or non-repairable state. |
| `Remediate-ComponentStore.ps1` | Runs RestoreHealth only for a repairable image and verifies with ScanHealth. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Upload `Detect-ComponentStore.ps1` and `Remediate-ComponentStore.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**, unless signing the scripts first.
4. Start with **Once** on a small affected device group during maintenance. Measure scan and repair duration before recurring use.
5. Review detection and remediation output before expanding the assignment.

## Notes

- Windows 10/11 clients only. Repair is enabled by default; set `$EnableRemediation = $false` to pause repairs.
- Empty `$RepairSources` uses the Windows repair source policy and Windows Update where allowed; no policy is changed.
- Optional sources must match Windows version, architecture, languages and servicing level. SYSTEM needs access; `$LimitAccess = $true` requires an explicit source.
- Non-repairable images need manual recovery. Error 0x800f081f can also mean missing source files without corruption; this script does not install .NET 3.5.
- No automatic restart or servicing-process termination. PendingRestart needs maintenance; long operations can exceed Intune's execution window. Review Windows DISM and CBS logs for errors.
