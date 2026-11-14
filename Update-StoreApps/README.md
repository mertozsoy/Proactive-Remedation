# Update Store Apps

Photos and Snipping Tool can remain outdated when Store servicing is restricted. This Intune Remediations script pair requests an app update scan through the documented MDM bridge and checks the method return value. It does not verify installed versions or bypass Store restrictions.

## Files

| File | Purpose |
|---|---|
| `Detect-StoreApps.ps1` | Checks device applicability and the AppManagement instance. Reports LastScanError and returns 1 to request a scheduled scan. |
| `Remediate-StoreApps.ps1` | Invokes UpdateScanMethod once. Returns 0 only for a zero method result, report mode or a not-applicable device. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-StoreApps.ps1` and `Remediate-StoreApps.ps1`.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for these unsigned files; use your signing process if required.
4. Assign a pilot device group. Schedule: Daily, or use an on-demand run for troubleshooting.
5. Review remediation output and separately confirm the affected app versions and Defender vulnerability findings before expanding deployment.

## Notes

- Requires a supported Windows 10/11 client, LocalSystem context and the device MDM bridge instance. Store connectivity and app servicing must be permitted; the scripts do not bypass policy.
- `$EnableUpdateScan` defaults to `$true`. Set it to `$false` in both scripts for report-only mode; restore `$true` in both to enable requests. Keep `$CimTimeoutSeconds` identical; check servicing before retrying a timeout.
- Risk: the device-context scan has no app filter and can affect other eligible Store apps. Test in a pilot group before expanding deployment.
- `ScanDue` returns exit 1 on every applicable enabled run, even after remediation. `Requested` confirms only a zero method result; verify app versions and Defender findings separately. `LastScanError` may be stale.
- No apps are removed or forcibly closed; no restart or sign-out is requested. Best-effort logs use `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT_StoreApps.log`.
