# Remove PowerShell V2

Intune Remediations script pair. PowerShell 2.0 has no AMSI and no script block logging, and `powershell -Version 2` is a known way to get around both. This pair removes the engine.

## Files

| File | Purpose |
|---|---|
| `Detect-PowerShellV2.ps1` | Checks the MicrosoftWindowsPowerShellV2Root and MicrosoftWindowsPowerShellV2 features. Builds that no longer include them are compliant. |
| `Remediate-PowerShellV2.ps1` | Disables the features without a restart. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-PowerShellV2.ps1` as the detection script and `Remediate-PowerShellV2.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Weekly.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Make sure no old tool still calls `-Version 2`.
