# Remove WSUS Policy Leftovers

Intune Remediations script pair. After moving to Windows Update for Business or Autopatch, old WSUS values stay on the device and keep it scanning WSUS or block updates completely.

## Files

| File | Purpose |
|---|---|
| `Detect-WSUSPolicyLeftovers.ps1` | Checks WUServer, WUStatusServer, UpdateServiceUrlAlternate, DoNotConnectToWindowsUpdateInternetLocations, DisableWindowsUpdateAccess, UseWUServer and NoAutoUpdate. ConfigMgr clients are skipped. |
| `Remediate-WSUSPolicyLeftovers.ps1` | Exports a .reg backup, removes only those values and restarts wuauserv. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-WSUSPolicyLeftovers.ps1` as the detection script and `Remediate-WSUSPolicyLeftovers.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- If a GPO still sets these values, fix the GPO first or they will come back.
