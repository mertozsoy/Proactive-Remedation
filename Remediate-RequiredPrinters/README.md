# Remediate Required Printers

Required branch printers may be missing from the user's printer list after moving away from GPO mapping. These scripts compare installed connections with an approved list and add missing shared printers in the signed-in user's context.

## Files

| File | Purpose |
|---|---|
| `Detect-RequiredPrinters.ps1` | Checks approved UNC connections and reports the missing count. |
| `Remediate-RequiredPrinters.ps1` | Adds missing connections with Add-Printer and verifies the installed list. |

## Deployment (Intune)

1. Set `$RequiredPrinters` identically in both scripts, for example `@('\\print01.contoso.local\BranchPrinter')`.
2. Go to **Devices > Manage devices > Scripts and remediations > Remediations > Create script package**.
3. Upload the detection and remediation files.
4. Run this script using the logged-on credentials: **Yes**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to the appropriate branch user group. Start with a pilot and schedule hourly.

## Notes

- The list starts empty and returns NotApplicable until configured. Use the exact UNC connection names shown by Get-Printer; aliases are not resolved.
- Users need print permissions and access to the print server through the office network or VPN. Missing connections remain failures when access is unavailable.
- Predeploy approved signed drivers with administrative tooling if required. Point and Print restrictions are never relaxed.
- Existing printers and default printer settings are left alone. Avoid overlapping policies that remove the same connections.
- This checks connection presence only, not print job delivery. Logs contain counts and error codes without user or printer names.
