# Remove Defender Local Exclusions

Local admins can add Microsoft Defender Antivirus exclusions that are outside Intune policy. Those entries stay on the device and silently widen the scan gap. This pair finds the exclusions that are not set by policy and removes them after backing up the exclusion key.

## Files

| File | Purpose |
|---|---|
| `Detect-DefenderLocalExclusions.ps1` | Compares the effective exclusion list from `Get-MpPreference` with the exclusions under the policy key and lists the local paths, extensions and processes. `$IgnorePaths` keeps known good entries. |
| `Remediate-DefenderLocalExclusions.ps1` | Backs up the exclusion registry key with `reg export` and removes each local entry with `Remove-MpPreference`. Policy exclusions are never touched. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-DefenderLocalExclusions.ps1` as the detection script and `Remediate-DefenderLocalExclusions.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Only path, extension and process exclusions are checked. IP address exclusions are left alone.
- Tamper protection can block the change. The script then exits 1 and the output shows `TamperProtected=True`.
- A tool that re-adds its own exclusion keeps the device in drift. Use `$IgnorePaths` for entries you want to keep.
- `$EnableRemediation = $false` by default: the pair only reports. Legitimate apps such as backup or database agents often add their own exclusions. Review the list, add the ones you keep to `$IgnorePaths`, then enable removal.
