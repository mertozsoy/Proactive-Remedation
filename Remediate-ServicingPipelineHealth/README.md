# Remediate Servicing Pipeline Health

Intune Remediations script pair. Devices that show up as Unknown in Windows Update for Business reports, Autopatch or the Secure Boot status report usually have one broken link in the client side pipeline. Debloat scripts and hardened images often disable DiagTrack, wlidsvc or the appraiser tasks. This pair finds the broken component and puts it back to the Windows default.

## Files

| File | Purpose |
|---|---|
| `Detect-ServicingPipelineHealth.ps1` | Checks DiagTrack, wlidsvc, the Compatibility Appraiser and Census tasks, the Secure-Boot-Update task and the Update Orchestrator scan task. Components changed by policy are reported as ATTENTION and left alone. Exits `1` only when something can safely be set back to default. |
| `Remediate-ServicingPipelineHealth.ps1` | Sets service start types and scheduled task states back to their Windows defaults and checks the result. DiagTrack is not touched when AllowTelemetry is 0. The Secure-Boot-Update task is only reported. Set `$DryRun = $true` to see what would change without changing it. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-ServicingPipelineHealth.ps1` as the detection script and `Remediate-ServicingPipelineHealth.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- If a GPO or Settings Catalog profile disables one of these components, the script reports it and does not override it. Fix it at the policy level.
- `$ReportAttentionAsIssue = $true` makes policy owned findings exit `1` so they show up under With issues.
- Log: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT-REM-001.log`
