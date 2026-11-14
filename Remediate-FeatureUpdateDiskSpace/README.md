# Remediate Feature Update Disk Space

Low free space can block a Windows feature update. These scripts check the Windows system drive against a configurable target and clear unpinned Delivery Optimization cache, then clean superseded Windows components if more space is needed.

## Files

| File | Purpose |
|---|---|
| `Detect-FeatureUpdateDiskSpace.ps1` | Reports drift when system drive free space is below `$MinimumFreeGB`. |
| `Remediate-FeatureUpdateDiskSpace.ps1` | Performs staged cleanup and checks the free space again. Returns failure if the target is not met. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload the detection and remediation scripts in the Files table.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Enforce script signature check: **No**, unless signed with a trusted certificate.
5. Set the same `$MinimumFreeGB` in both scripts. Assign to a pilot device group before the feature update and schedule daily.

## Notes

- Windows 10 build 19041 or later clients only. The default 30 GiB target is an operational buffer, not an upgrade eligibility guarantee.
- User files, Recycle Bin, Windows.old and installer caches are untouched. Pinned Delivery Optimization files are retained; no policies are changed.
- DISM removes superseded components without the usual 30-day grace period. `/ResetBase` is not used; test rollback requirements first.
- Active setup, servicing or Delivery Optimization downloads defer cleanup. Unavailable or failed cache cleanup is reported; component cleanup can still proceed.
- DISM is observed for up to 600 seconds, then left running as Pending. No reboot is requested; unresolved space or a nonzero DISM code returns failure.
