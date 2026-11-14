# Remediate Windows Activation

Intune Remediations script pair. Devices lose activation after a motherboard change, a KMS problem or a failed Enterprise subscription step up. This pair finds them and retries activation.

## Files

| File | Purpose |
|---|---|
| `Detect-WindowsActivation.ps1` | Reads LicenseStatus for Windows (1 = Licensed) and reports the edition and channel. |
| `Remediate-WindowsActivation.ps1` | Starts sppsvc and ClipSVC if disabled, runs the subscription activation tasks and `slmgr /ato`. The product key is never changed. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-WindowsActivation.ps1` as the detection script and `Remediate-WindowsActivation.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- If activation still fails, the output shows the last status so you can see whether it is a KMS, MAK or subscription issue.
