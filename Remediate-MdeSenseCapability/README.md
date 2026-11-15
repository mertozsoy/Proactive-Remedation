# Remediate MDE Sense Capability

Some Windows 11 24H2 OEM images ship without the SENSE Client feature on demand. The Sense service never starts, so Microsoft Defender for Endpoint onboarding fails and the device never shows up in the Defender portal. These scripts check the capability and install it with DISM.

## Files

| File | Purpose |
|---|---|
| `Detect-MdeSenseCapability.ps1` | Checks the build and edition, then the state of the `Microsoft.Windows.Sense.Client` capability and the Sense service. Returns 1 when the capability is not installed on a supported device. |
| `Remediate-MdeSenseCapability.ps1` | Installs the capability with `Add-WindowsCapability`, verifies the state and starts the Sense service when it is stopped. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Name: **Remediate - MDE Sense Capability**. Upload the detection and remediation scripts.
3. Run this script using the logged-on credentials: **No**.
4. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot device group. Schedule daily and review results before expanding.

## Notes

- The capability is available on Windows 11 24H2 and later only. Home editions are reported as NotApplicable.
- Installation without a source uses Windows Update. Set `$SourcePath` to a mounted Features on Demand source for devices without access.
- The script does not restart the device and does not restart IME. A pending restart is reported in the output.
- Onboarding itself is not part of this script. Run the Defender onboarding policy after the capability is installed.
