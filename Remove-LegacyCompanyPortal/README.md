# Remove Legacy Company Portal

Intune Remediations script pair. A Company Portal copy that was installed per user from the old Store blocks the Microsoft Store app (new) install in system context. This pair finds devices where Company Portal exists only as a per-user install and removes that copy so the Intune assignment can install it for the device.

## Files

| File | Purpose |
|---|---|
| `Detect-LegacyCompanyPortal.ps1` | Reads `Get-AppxPackage -AllUsers` and `Get-AppxProvisionedPackage -Online` for `Microsoft.CompanyPortal`. Flags the device when the app is installed for users but not provisioned. |
| `Remediate-LegacyCompanyPortal.ps1` | Removes the package for all users with `Remove-AppxPackage -AllUsers` and checks that no copy is left. Does nothing if the app is provisioned. Waits for the next run if Company Portal is open. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-LegacyCompanyPortal.ps1` as the detection script and `Remediate-LegacyCompanyPortal.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Use this only where Company Portal is assigned as a required Microsoft Store app (new) with install behavior **System**. If you deploy it in user context, a per-user install is the expected state and this pair must not be assigned.
- The script does not install Company Portal. Intune installs it again on the next app evaluation. Users are without the app in between, so pilot first.
- The script does not touch the Intune Management Extension service or its retry state.
- Company Portal is not closed by the script. An open app defers the removal to the next run.
