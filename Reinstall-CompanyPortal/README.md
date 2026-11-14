# Reinstall Company Portal

Intune Remediations script pair. Company Portal can disappear from a device or stay registered with an empty install folder after a feature update, a cleanup tool or a failed Store deployment. Users then cannot open the app. This pair detects the broken state and installs the app again from a staged msixbundle or resets the registration so the Intune Store app deploys it again.

## Files

| File | Purpose |
|---|---|
| `Detect-CompanyPortal.ps1` | Reads `Get-AppxPackage -AllUsers` and `Get-AppxProvisionedPackage -Online` for `Microsoft.CompanyPortal`. Counts registered users from `PackageUserInformation` and checks `InstallLocation` plus `AppxManifest.xml`. Reports Missing, NotRegistered, Broken or NotProvisioned and exits 1. Server OS returns NotApplicable. |
| `Remediate-CompanyPortal.ps1` | Removes a broken registration. When `$PackagePath` exists, removes the old provisioned entry and provisions the bundle with `Add-AppxProvisionedPackage`. Without a bundle, and with `$ResetForReinstall` on, removes the provisioned entry so the Store app assignment reinstalls the app. Verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-CompanyPortal.ps1` as the detection script and `Remediate-CompanyPortal.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Keep Company Portal assigned as a required Microsoft Store app (new) with install behavior **System**. The reset path depends on that assignment to install the app again. Without it the device stays without Company Portal after the reset.
- Optional offline repair: copy `Microsoft.CompanyPortal.msixbundle` to `C:\ProgramData\IntuneRemediations\Source\`. The script provisions it with `Add-AppxProvisionedPackage` and skips the license by default. Set `$DependencyPath` for dependency files and `$LicensePath` for a license file.
- Provisioning applies to users at their next sign-in. Between the run and the sign-in, detection keeps reporting the app as not registered.
- Removal clears the app registration and the app local data. The device record and the enrollment are not touched. The app rebuilds its cache at the next start.
- The script does not close a running Company Portal. An open app defers the removal to the next run.
- `$ResetForReinstall` is `$false` by default. Without a staged bundle the script only reports. Turn it on only when a Company Portal Store app is assigned to devices in System context, because the reset removes the app from every user until Intune installs it again.
- No restart, no IME service restart and no user sign-out.
- Localized Windows is supported because the script reads CIM, Appx objects and file paths, not command output.
