# Disable WinRM Basic Auth

WinRM still accepts Basic authentication and unencrypted traffic on some clients after an old image or a manual `winrm quickconfig`. Audit and security scans flag these devices. This pair sets the WinRM client and service policy values to block Basic and unencrypted traffic, applies the same values to the live WinRM configuration and verifies both sides.

## Files

| File | Purpose |
|---|---|
| `Detect-WinRMBasicAuth.ps1` | Reads `AllowBasic` and `AllowUnencryptedTraffic` under the WinRM client and service policy keys plus the live WinRM configuration. Exits 1 on drift. |
| `Remediate-WinRMBasicAuth.ps1` | Exports the two policy keys, sets the four values to 0 and applies the same values with `winrm.exe`. Verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-WinRMBasicAuth.ps1` as the detection script and `Remediate-WinRMBasicAuth.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, then widen the scope.

## Notes

- Basic authentication is used by some monitoring tools and non-domain clients. Check the inventory before you assign the pair to the whole fleet.
- When the WinRM service is stopped the service side is skipped and only the client values are changed. The output shows `LiveApply=AppliedClientOnly` in that case.
- `$ApplyLiveConfig = $false` limits the script to the policy keys.
- Backups of the two policy keys go to `%ProgramData%\IntuneRemediations\Backup\WinRMBasicAuth`.
- A device that reads the policy from GPO or Intune gets the same values on the next policy refresh. The script does not change any other WinRM setting.
