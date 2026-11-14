# Set Update Health Tools

Windows needs the Microsoft Update Health Tools to support expedited quality updates on versions earlier than 24H2. On Windows 11 24H2 and later Microsoft says not to install the tools. Devices that upgraded often keep the old MSI. This pair checks the service, the uninstall entry and the install folder and brings the device to the state that matches its build.

## Files

| File | Purpose |
|---|---|
| `Detect-UpdateHealthTools.ps1` | Reads the OS build from the registry. Flags the tools as missing below build 26100 and as leftover on 26100 and later. Presence is taken from the Microsoft Update Health Service, the uninstall entry or the install folder. |
| `Remediate-UpdateHealthTools.ps1` | Uninstalls the MSI with `msiexec /x` on 24H2 and later. Installs the MSI from `$HealthToolsMsiPath` below 24H2 when the tools are missing. Checks the service state afterwards. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-UpdateHealthTools.ps1` as the detection script and `Remediate-UpdateHealthTools.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- The expected state comes from the expedite policy documentation on Microsoft Learn: the tools are required before 24H2 and should not be installed on 24H2 and later.
- Removal uses the product code from the uninstall key under `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall` and runs `msiexec /x` with `/qn /norestart`. No registry key is deleted by hand, so no `reg export` is taken. Windows Installer removes its own entries.
- Install needs a package source. Download the MSI from KB4023057 or the Microsoft Download Center, place it on the device or on a share that the SYSTEM account can read, and set `$HealthToolsMsiPath` to that path. Without a path the script reports `Manual` and changes nothing.
- `$EnableRemediation` is `$true` by default. Set it to `$false` to keep the script in report mode while the pilot runs.
- The script does not restart the device and does not restart any service. A restart required by the installer is reported through the `ExitCode` value 3010 or 1641.
- Server SKUs exit `NotApplicable`. The tools are a client servicing component.
- Medium impact: the installer runs on the device. Start with a pilot group.
