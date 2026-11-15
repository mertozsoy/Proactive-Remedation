# Repair WMI Repository

An inconsistent WMI repository can break inventory and management queries. These scripts verify the live repository and run winmgmt salvage only when verification returns the repository corruption code.

## Files

| File | Purpose |
|---|---|
| `Detect-WmiRepository.ps1` | Checks repository consistency using numeric exit codes. |
| `Remediate-WmiRepository.ps1` | Rechecks the repository, salvages confirmed corruption and verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload the detection and remediation scripts from the Files table.
3. Run this script using the logged-on credentials: **No**.
4. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot device group and schedule daily.

## Notes

- Salvage is enabled by default. Set `$EnableRemediation = $false` to report without repair.
- Only error 1358 or its HRESULT equivalent triggers salvage; other errors block repair.
- No repository reset, deletion, bulk MOF registration or service restart is performed.
- Salvage merges readable content; consistency does not prove every application provider works.
- Each command has a 180-second timeout. A timed-out process is not killed; investigate before retrying.
