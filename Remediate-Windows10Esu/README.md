# Remediate Windows 10 ESU

Windows 10 support ended on 14 October 2025. A device without an activated Extended Security Updates key stops receiving critical and important security updates even when update policies are assigned. This pair checks the ESU product in the Software Licensing service and installs and activates the ESU MAK when it is missing.

## Files

| File | Purpose |
|---|---|
| `Detect-Windows10Esu.ps1` | Checks the OS build, resolves the ESU year and reads `LicenseStatus` of the ESU product. Exits 1 when the key is missing or not activated. |
| `Remediate-Windows10Esu.ps1` | Reads the ESU MAK, installs it with `slmgr.vbs /ipk`, activates it with `slmgr.vbs /ato` and verifies the license state. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-Windows10Esu.ps1` as detection and `Remediate-Windows10Esu.ps1` as remediation.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
4. Put the ESU MAK in `C:\ProgramData\IntuneRemediations\ESU\esu-mak.txt` on the device, or fill `$EsuMak` before upload.
5. Schedule: Daily. Assign to a small Windows 10 22H2 pilot group first.

## Notes

- Scope is Windows 10 build 19045 only. Windows 11 and earlier builds return `NotApplicable`. LTSC and LTSB releases are not covered by the ESU program.
- The device needs the ESU prerequisite updates and a restart before the key is installed. A missing prerequisite makes `/ipk` fail with 0xC004F050.
- Do not commit the MAK to the repository. Keep it in the key file or a secure variable and treat it as a license secret.
- `$EsuYear` stays 0 for automatic selection from the current date. Set 1, 2 or 3 only for a fixed ESU year.
- Activation needs access to the Microsoft activation endpoints. Offline devices fail as `Failed` with the license status in the output.
