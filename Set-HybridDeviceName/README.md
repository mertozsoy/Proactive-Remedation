# Set Hybrid Device Name

Hybrid joined Windows devices cannot use the Intune Rename action. These scripts compare approved hardware UUIDs with assigned names and use a domain-aware rename without restarting the device.

## Files

| File | Purpose |
|---|---|
| `Detect-HybridDeviceName.ps1` | Checks hybrid join, approved names and pending name changes. |
| `Remediate-HybridDeviceName.ps1` | Checks name availability in AD, renames the device and verifies the staged name. |

## Deployment (Intune)

1. Open **Devices > Manage devices > Scripts and remediations > Remediations > Create**.
2. Upload the detection and remediation scripts above.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**, unless signed with a trusted certificate.
4. Configure both scripts identically. Assign to a small approved hybrid device group and schedule daily.
5. Review detection output before enabling remediation. Plan a separate maintenance restart and verify the next detection result.

## Notes

- Set `$ExpectedDomain`, `$NamePattern` and `$ApprovedNames` in both scripts. Use uppercase SMBIOS UUID keys and unique approved names of at most 15 characters, for example `PC-IST001`.
- High risk: `$EnableRemediation = $false` by default. Enable only after checking naming policies, dependencies, AD name reservations and rollback approval; exclude devices managed by another naming mechanism.
- Set `$DomainCredentialPath` to an ACL-protected credential CLIXML file provisioned securely on each device as SYSTEM. Windows DPAPI requires the same device and identity; never distribute plaintext passwords or a shared encrypted export.
- The credential needs delegated rename rights on the approved AD computer objects. Do not use Domain Admin credentials; DC connectivity and SYSTEM read access to AD are required.
- PendingReboot is not final compliance. No automatic restart or registry editing occurs; confirm AD, DNS and cloud inventory after the planned restart. Rollback requires approving the previous name and repeating the domain rename.
