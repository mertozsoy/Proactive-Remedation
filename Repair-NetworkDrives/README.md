# Repair Network Drives

Intune Remediations script pair. Mapped drives drop after sleep or a VPN reconnect, or still point to a file server that was replaced, and Entra joined devices have no GPO to put them back. This pair compares the user's drives with an expected list and maps the missing ones again.

## Files

| File | Purpose |
|---|---|
| `Detect-NetworkDrives.ps1` | Runs as the user. For each entry in `$DriveMaps` checks the live mapping (`Win32_LogicalDisk`) and the saved one (`HKCU\Network`). Tests TCP 445 on the file server first, so an off network device is not flagged. |
| `Remediate-NetworkDrives.ps1` | Removes a stale or wrong mapping and maps the drive as persistent with `WScript.Network`. Uses the signed-in user's own credentials. Checks the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-NetworkDrives.ps1` as the detection script and `Remediate-NetworkDrives.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Hourly.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Edit `$DriveMaps` in both scripts and keep the lists identical. `fs01.contoso.local` is an example.
- No credentials are stored or passed. The user needs working single sign-on to the file server (Kerberos, or cloud Kerberos trust on Entra joined devices).
- If the letter belongs to a local or removable disk, the entry is reported as `LetterInUse` and left alone.
- `Offline` means the server did not answer on TCP 445 within `$PortTimeoutMs`. Nothing is changed in that case.
- Must run with the logged-on credentials. An hourly schedule suits VPN users.
