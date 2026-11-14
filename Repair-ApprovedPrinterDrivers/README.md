# Repair Approved Printer Drivers

Standard users may receive an administrator prompt when a shared printer needs a driver. These scripts preinstall approved drivers as SYSTEM so users can connect without downloading a new driver. Point and Print security settings remain unchanged.

## Files

| File | Purpose |
|---|---|
| `Detect-ApprovedPrinterDrivers.ps1` | Checks exact driver names and installed INF SHA256 hashes. |
| `Remediate-ApprovedPrinterDrivers.ps1` | Stages approved local drivers, installs them and verifies their INF hashes. |

## Deployment (Intune)

1. Obtain the signed x64 driver files matching the print server. Deploy the complete extracted driver directory through a SYSTEM Win32 app to a local location writable only by administrators and SYSTEM.
2. Populate `$ApprovedDrivers` identically in both scripts. Each entry is a hashtable with `Name` (exact installed driver name), `SourceInf` (absolute local INF path) and `InfSha256` (64-character SHA256 from the approved original INF). Example paths: `C:\ProgramData\Company\PrinterDrivers\Model\driver.inf`.
3. Confirm source permissions, driver approval and that no active policy prohibits the installation. Set `$ConfirmDeploymentApproved = $true` in remediation. Keep `$AllowDriverUpdate = $false` unless an existing-driver replacement is approved.
4. Go to **Devices > Scripts and remediations > Remediations > Create**. Select both scripts.
5. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
6. Assign a pilot device group after the source app is installed. Schedule daily and test a standard-user printer connection before wider assignment.

## Notes

- Supports patched x64 Windows clients and signed INF-based drivers. ARM64, vendor setup applications and Windows protected print mode are outside scope.
- An empty approval list fails closed. Missing sources, hash mismatches and a stopped Spooler are failures or blockers, not healthy results.
- Driver updates are disabled by default. Approved replacements can affect existing queues; no drivers or queues are removed and no restart is forced.
- Server and client driver versions must match. Queue access and server restrictions still apply; verification is local driver readiness, not a print test.
- No registry or policy edits. Logs: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT_ApprovedPrinterDrivers.log`. PnPUtil validates catalog signing; the INF hash identifies the approved release, not every file.
