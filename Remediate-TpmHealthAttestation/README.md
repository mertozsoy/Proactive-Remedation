# Remediate TPM Health Attestation

Intune Remediations script pair for devices that show as noncompliant for BitLocker, Secure Boot or Code Integrity because the TPM health attestation certificate was never cached. The detection script checks the cached certificate status and the remediation script starts the built-in retrieval task.

## Files

| File | Purpose |
|---|---|
| `Detect-TpmHealthAttestation.ps1` | Reads the TPM state and the `Status` value under the TPM `HealthCert` store. Exits 1 when the TPM is ready but the certificate is missing or not valid. |
| `Remediate-TpmHealthAttestation.ps1` | Starts the `Tpm-HASCertRetr` task under `\Microsoft\Windows\TPM`, waits for it to finish and checks the certificate status again. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-TpmHealthAttestation.ps1` as the detection script and `Remediate-TpmHealthAttestation.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- A device needs TPM 2.0 in the enabled and activated state. Other devices exit as NotApplicable. Fix the TPM state in UEFI first.
- Retrieval needs outbound HTTPS access to `has.spserv.microsoft.com` and `*.microsoftaik.azure.net`.
- `$WaitSeconds` sets how long the script waits for the task.
- The certificate store path and task name come from Microsoft support guidance, not from a public CSP page.
- Intune compliance updates on the next device check-in, not right after the task finishes.
