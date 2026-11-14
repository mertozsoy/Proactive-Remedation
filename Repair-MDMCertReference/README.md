# Repair MDM Cert Reference

An MDM certificate renewal can leave the device with a valid new certificate but no SslClientCertReference in the OMA-DM account. Sync then fails with 0x80190190 or 400 Bad Request and the device looks broken until it is re-enrolled. These scripts compare the reference with the certificate on the device and restore it.

## Files

| File | Purpose |
|---|---|
| `Detect-MDMCertReference.ps1` | Finds the Intune enrollment, reads `DMPCertThumbPrint` and `SslClientCertReference`, and checks that the referenced certificate exists in LocalMachine My with a private key. Exits `1` when the reference is missing or stale. |
| `Remediate-MDMCertReference.ps1` | Exports the OMA-DM account key, writes `MY;System;<thumbprint>`, verifies the value and starts the EnterpriseMgmt sync task. Report only by default. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-MDMCertReference.ps1` as the detection script and `Remediate-MDMCertReference.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Review the report-only output on a pilot group. Then set `$EnableRemediation = $true` in the remediation script.
5. Schedule daily and widen the assignment after the pilot devices sync again.

## Notes

- High impact: the remediation writes to the MDM enrollment registry and stays in report mode until `$EnableRemediation` is set to `$true`.
- The value is built from `DMPCertThumbPrint`. If no usable MDM certificate exists the scripts stop and ask for re-enrollment instead of writing a reference.
- The OMA-DM account key is exported with `reg.exe` to `%ProgramData%\IntuneRemediations\Backup\MDMCertReference` before the value is written.
- `SslClientCertSearchCriteria` is reported only. That value is tied to the device EntDMID and is not rebuilt by these scripts.
- No service restart and no reboot. The sync is started from the EnterpriseMgmt PushLaunch task when it exists.
