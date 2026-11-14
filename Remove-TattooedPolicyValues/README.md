# Remove Tattooed Policy Values

Removed Settings Catalog or ADMX assignments can leave registry values behind. These scripts detect an explicit retirement list and remove exact matches after approval and registry backup. They do not remove ADMX ingestion state or repair event 454.

## Files

| File | Purpose |
|---|---|
| Detect-TattooedPolicyValues.ps1 | Checks exact machine policy value names, types and data. |
| Remediate-TattooedPolicyValues.ps1 | Exports parent keys, deletes approved matching values and verifies absence. |

## Deployment (Intune)

1. Fill the same RetiredValues list in both scripts. The empty default returns NotApplicable. Example syntax:

```powershell
$RetiredValues = @(
    @{
        Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        Name = 'HideFirstRunExperience'
        Kind = 'DWord'
        Data = 1
        SourcesRetired = $false
    }
)
```

2. Review Intune assignments, local and domain GPO, browser cloud management and other writers for each target. Remove the source configuration and let devices sync. Set SourcesRetired to true only after confirming that no active source manages that value.
3. After a report-only pilot, set EnableRemediation to true and ApprovalExpiresUtc to an explicit future UTC time in yyyy-MM-ddTHH:mm:ssZ format, at most seven days ahead. Use a short one-time cleanup window, then remove the assignment.
4. Go to **Devices > Scripts and remediations > Remediations > Create**. Upload both scripts. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**, unless signed under your signing policy.
5. Assign to a small device group first. Review detection and remediation output before widening scope.

## Notes

- Default deletion is off; source retirement is an administrator attestation, not automatic policy-source discovery.
- Only explicit HKLM SOFTWARE Policies subkeys and String or DWord values are supported; mismatches block the entire cleanup.
- Backups are in %ProgramData%\IntuneRemediations\Backup\TattooedPolicyValues. Review before reg import because exports contain the whole parent key.
- No user hives, browser data, PolicyManager or ADMX ingestion keys are deleted; ADMX event 454 needs separate diagnosis.
- Registry absence is verified immediately, not future policy convergence. If values return, stop the cleanup and investigate the writer; browser refresh or a user-planned restart may be needed.
