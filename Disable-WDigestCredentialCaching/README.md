# Disable WDigest Credential Caching

WDigest authentication makes LSASS keep a copy of the user's plaintext password in memory. Windows 10 and Windows 11 leave this off by default. An old image, a legacy GPO or a manual registry tweak can still set UseLogonCredential back to 1 and security scans report it. This pair sets the value to 0 and verifies the result.

## Files

| File | Purpose |
|---|---|
| `Detect-WDigestCredentialCaching.ps1` | Reads `UseLogonCredential` under the WDigest security provider key. Exits 1 when the value is set to anything other than 0, 0 when it is 0 or not set. |
| `Remediate-WDigestCredentialCaching.ps1` | Exports the WDigest key, sets `UseLogonCredential` to 0 and reads the value back. Exits 0 only when caching is disabled. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-WDigestCredentialCaching.ps1` as the detection script and `Remediate-WDigestCredentialCaching.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, then widen the scope.

## Notes

- On a clean Windows 10 or 11 device the value is not present. A missing value means caching is disabled and the script reports `Unset` as healthy.
- Backups of the WDigest key go to `%ProgramData%\IntuneRemediations\Backup\WDigestCredentialCaching`.
- The script does not restart the device. Plaintext copies that are already in LSASS memory for open sessions are cleared only after a restart.
- If a GPO or another tool writes the value back to 1 the drift returns on the next policy refresh. Fix that source policy, not only the device.
- Microsoft is deprecating WDigest. Applications that still need it will fail to authenticate once the value is 0.
