# Remediate Time Sync

Intune Remediations script pair. A drifting clock breaks Kerberos, PRT and TLS, and usually nobody notices until sign in fails. This pair keeps Windows time healthy.

## Files

| File | Purpose |
|---|---|
| `Detect-TimeSync.ps1` | Checks the W32Time service, a time source that fell back to the local clock and the offset against the source with `w32tm /stripchart` (`$MaxOffsetSeconds` 60). Works on Turkish and English Windows. |
| `Remediate-TimeSync.ps1` | Domain and hybrid joined devices use `domhier`; Entra joined and workgroup devices use `$NtpPeer` (`time.windows.com,0x9`). Restarts W32Time and forces a resync. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-TimeSync.ps1` as the detection script and `Remediate-TimeSync.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- If the time source cannot be reached (device off network), the offset is not flagged.
