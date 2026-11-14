# Repair Cisco VPN Profile

Cisco Secure Client can be installed while its corporate VPN profile XML is missing. These scripts detect the missing file and restore an approved copy without overwriting existing profiles or restarting the VPN service.

## Files

| File | Purpose |
|---|---|
| `Detect-CiscoVpnProfile.ps1` | Checks the named profile and basic XML structure on Secure Client devices. |
| `Remediate-CiscoVpnProfile.ps1` | Restores the missing XML from embedded Base64 and verifies XML and SHA256. |

## Deployment (Intune)

1. Export your approved VPN XML using Cisco's profile tools. Set `$ProfileFileName` to its original file name in both scripts. Names must use letters, digits, underscores or hyphens and end in `.xml`.
2. Encode the original file bytes with `[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\Approved\CorporateVpn.xml'))`. Paste the result into `$ApprovedProfileBase64` in the remediation script. Do not include credentials. Base64 is not encryption.
3. Go to **Devices > Manage devices > Scripts and remediations > Create script package**. Upload both scripts.
4. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**, unless using trusted signed scripts.
5. Schedule daily and assign to a pilot device group with the VPN module enabled before widening the scope.

## Notes

- Targets Secure Client 5.x at `%ProgramData%\Cisco\Cisco Secure Client\VPN\Profile`; legacy AnyConnect and management tunnel profiles are excluded.
- Restore only. Existing invalid XML requires manual review; valid files are not compared with the approved baseline. Exclude devices where another deployment intentionally removes this profile.
- An empty or invalid approved payload fails remediation. Use a Cisco-validated profile; the script checks XML structure, not the full Cisco schema or VPN connectivity.
- No download, service restart, disconnect or certificate change. A restored profile may require reopening the client UI during a suitable user-controlled window.
- Logs: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT_CiscoVpnProfile.log`. Output omits server addresses and XML content.
