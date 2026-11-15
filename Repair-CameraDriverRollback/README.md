# Repair Camera Driver Rollback

A known bad camera driver can leave a specific computer model without video. These scripts detect that exact driver and use Windows driver rollback to restore its previous backup driver, then verify the approved version and device status.

## Files

| File | Purpose |
|---|---|
| `Detect-CameraDriverRollback.ps1` | Checks the exact model, camera hardware ID, driver version and device error code. |
| `Remediate-CameraDriverRollback.ps1` | Calls DiRollbackDriver without UI and verifies the expected signed driver and device status. |

## Deployment (Intune)

1. Set `TargetModel`, `TargetHardwareId`, `BadDriverVersions`, `ExpectedDriverVersion` and `ExpectedDriverProvider` identically in both scripts. Use the exact model from Win32_ComputerSystem and the camera's hardware ID from Device Manager. The approved version must be older than every bad version.
2. Review Intune driver update assignments, Windows Update and GPO. Remove conflicting driver deployment at its source. Confirm the Windows backup driver is the approved version on pilot devices, then set `DriverPolicyReviewApproved` and `EnableRemediation` to `$true` in remediation.
3. Go to **Devices > Manage devices > Scripts and remediations > Create script package**. Upload the detection and remediation files.
4. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a small affected model group first. Schedule outside meetings, initially once daily. Validate camera video manually before expanding.

## Notes

- Rollback defaults to disabled because it interrupts camera use; empty target settings return `NotApplicable`.
- Only one present Camera or Image device may match. Unknown versions, providers and ambiguous matches are not changed.
- Windows selects its single backup driver, not an arbitrary INF. No backup returns `Failed`; an unexpected restored version fails verification.
- Policy review is an operator approval, not automatic assignment discovery. No policy is overwritten or driver update blocked locally.
- No restart is initiated. `PendingReboot` exits 1; verified signed version and device code 0 exit 0. This is not a video capture test.
