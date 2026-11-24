# Repair Registry.pol

Intune Remediations script pair for machines where Group Policy stops applying because the local Registry.pol file is damaged. Event 1096 in the Group Policy operational log points at that file on most of these machines. The scripts check the file structure and rebuild the file when it is broken.

## Files

| File | Purpose |
|---|---|
| `Detect-RegistryPol.ps1` | Checks the PReg signature, version, first record start and last record end of `%SystemRoot%\System32\GroupPolicy\Machine\Registry.pol`, and counts event 1096 for the last 7 days. |
| `Remediate-RegistryPol.ps1` | Copies the damaged file to a backup folder, replaces it with an empty valid header, runs `gpupdate /force` and validates the file again. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-RegistryPol.ps1` as the detection script and `Remediate-RegistryPol.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Medium impact: the policy store is replaced and `gpupdate /force` runs during the remediation window. Use a pilot group.
- Local policy settings that only exist in that file are lost. The original file and `gpt.ini` stay in `%ProgramData%\IntuneRemediations\Backup\RegistryPol`.
- Registry values already written by the damaged policy stay in the registry. This pair does not remove them.
- The check covers signature, version, record start and record end. Damage inside a record shows up as a high event 1096 count instead.
- Only Group Policy reads this file. Intune policy applied through the PolicyManager CSP is not affected.
