# Report IME Version

Detection only script for Intune Remediations. Devices on an Intune Management Extension version older than 1.58.103.0 stop receiving Win32 apps, PowerShell scripts, remediations and platform scripts. This script reports the installed version so those devices can be found before the helpdesk notice.

## Files

| File | Purpose |
|---|---|
| `Detect-IMEVersion.ps1` | Reads the agent executable file version and the uninstall registry entries, compares the highest value with `$MinimumVersion` (1.58.103.0) and exits 1 when the version is older or cannot be read. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-IMEVersion.ps1` as the detection script. Leave the remediation script empty.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Weekly.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Report only. The extension updates itself, so the fix is a device sync or a reinstall of the agent from the Intune side.
- The version comes from `Microsoft.Management.Services.IntuneWindowsAgent.exe` under `C:\Program Files (x86)\Microsoft Intune Management Extension`. Uninstall registry entries are used as a fallback.
- When no agent file and no registry entry exist the script exits 0 with NotApplicable. Devices that never received a Win32 app or a script fall into this group.
- Devices with an old version usually still check in. Absence of a recent check-in is a separate problem and is not part of this check.
- A version that cannot be parsed exits 1 as Unknown. Check the log before changing the device.
