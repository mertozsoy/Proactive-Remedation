# Uninstall OEM Trialware

OEM images can include unwanted security trials and Dell SupportAssist. These scripts find exact product names in machine uninstall registrations and remove matching MSI installations without restarting Windows. Non-MSI installations remain flagged.

## Files

| File | Purpose |
|---|---|
| `Detect-OemTrialware.ps1` | Checks both registry views for selected products and reports non-MSI counts. |
| `Remediate-OemTrialware.ps1` | Removes selected MSI products with msiexec and verifies that their registrations disappear. |

## Deployment (Intune)

1. Review `$TargetNames` and `$ExcludedProductCodes` in both scripts. Keep them identical. Remove required application assignments for these products before deployment.
2. Go to **Devices > Scripts and remediations > Remediations > Create** and upload both scripts.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
4. Verify replacement endpoint protection and approve security removal before setting `$AllowSecuritySoftwareRemoval = $true`.
5. Assign to a pilot device group and schedule daily. Check results before expanding.

## Notes

- Exact names only; per-user apps, Store apps and unlisted OEM components are outside scope.
- Security removal is disabled by default. Dell MSI removal is enabled; exclusions preserve approved products.
- EXE uninstall switches are not verified. Non-MSI products require a vendor-approved uninstall deployment.
- No forced restart, service changes or manual registry deletion. MSI code 3010 reports a pending restart.
- Up to three MSI removals per run; installer timeout stops further attempts without killing the installer. Remaining products return failure.
