# Remove Plaintext AutoLogon Password

Finds the DefaultPassword value under HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon without reading the password. After approval, removes only that value and verifies its absence.

## Files

| File | Purpose |
|---|---|
| `Detect-PlaintextAutoLogonPassword.ps1` | Flags DefaultPassword by name, even when empty or AutoLogon is disabled. |
| `Remediate-PlaintextAutoLogonPassword.ps1` | Removes DefaultPassword after both approval switches are enabled and verifies removal. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload the detection and remediation scripts from the Files table.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Enforce script signature check: **No**, unless signed under your signing policy.
5. Review GPO, Intune and provisioning ownership. Remove any source that recreates the value before setting `$ConfigurationSourceReviewed = $true`.
6. Confirm alternative sign-in for kiosk/POS devices. Set `$EnableRemediation = $true` to approve removal. Assign a pilot group and schedule daily.

## Notes

- Both approval switches default to false; blocked cleanup exits 1 and leaves detection unresolved.
- Removing DefaultPassword can stop subsequent automatic logon; no restart or sign-out is requested.
- Policy ownership cannot be inferred from this value; keep source approval false on actively managed devices.
- No registry key is deleted and no password backup is created. Passwords and account names are never logged.
- LSA secrets and other Winlogon values are untouched. Assess credential rotation and any required AutoLogon replacement separately.
