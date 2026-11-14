# Repair SCEP Wi-Fi Connection

A machine EAP-TLS Wi-Fi profile can arrive before its SCEP certificate and remain disconnected after certificate delivery. These scripts detect that state and request one connection using the existing profile once a matching machine certificate is ready.

## Files

| File | Purpose |
|---|---|
| `Detect-ScepWifiConnection.ps1` | Checks the machine Wi-Fi profile, certificate readiness and current connection. |
| `Remediate-ScepWifiConnection.ps1` | Connects a disconnected WLAN interface and verifies the exact target profile within the timeout. |

## Deployment (Intune)

1. Set `$WifiProfileName` to the exact Windows profile name and `$CertificateIssuer` to the issuing CA's full certificate Issuer distinguished name in both scripts. Keep their shared settings identical.
2. Go to **Devices > Scripts and remediations > Remediations > Create**.
3. Upload the detection and remediation scripts.
4. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot device group. Schedule hourly during provisioning, then reduce frequency or remove the assignment.

## Notes

- Supports all-user infrastructure profiles with explicit `machine` authentication and EAP-TLS certificate-store credentials. User certificates and `machineOrUser` profiles are not supported.
- Requires exactly one issuer-matching certificate with a private key, valid dates and the required EKUs. Add a dedicated certificate EKU to narrow selection if needed; Windows and RADIUS still validate trust, revocation, certificate selection and authorization.
- Set `$InterfaceGuid` when multiple WLAN interfaces exist. Other connected Wi-Fi networks are preserved; busy interfaces, missing profiles, unavailable certificates and API access errors block the attempt.
- Makes one connection request per run, with a 45-second verification window. It does not alter profiles, policy, services or certificates; access denial is reported without changing location permissions.
- Delivery requires an existing management connection such as Ethernet. A fully offline device cannot receive the scripts or certificate; out-of-range networks and RADIUS failures remain unsuccessful.
