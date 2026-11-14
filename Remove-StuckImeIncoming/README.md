# Remove Stuck IME Incoming Downloads

A Win32 app download can leave an old zero-byte file in IME Content\Incoming. These scripts identify unchanged candidates and remove only those that can be opened without allowing concurrent reads or writes.

## Files

| File | Purpose |
|---|---|
| `Detect-StuckImeIncoming.ps1` | Checks old zero-byte GUID_version.bin files twice and reports the count. |
| `Remediate-StuckImeIncoming.ps1` | Rechecks candidates, skips busy or changed files, deletes eligible files and verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-StuckImeIncoming.ps1` and `Remediate-StuckImeIncoming.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Schedule: Daily.
5. Assign to a pilot group before widening the scope.

## Notes

- Keep thresholds identical: minimum age 24 hours and observation 30 seconds by default; age does not prove an abandoned download.
- Only top-level GUID_version.bin files with zero length and old creation and write times qualify; reparse points are rejected.
- Busy or changed files are deferred. Remaining stale candidates return failure.
- Cleanup is enabled by default; set `$EnableRemediation = $false` for observation only.
- No service restart or retry-state reset occurs. Cleanup does not guarantee a new download or successful installation; investigate proxy, Delivery Optimization and IME logs if it recurs.
