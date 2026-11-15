# Enable WinHTTP Auto-Proxy Service

Windows 11 24H2 added WinHttpAutoProxySvc to the dependency list of the Windows Connection Manager service. Devices where WPAD hardening disabled that service lose their network profile after the upgrade. This pair puts the service back to Manual and starts the connection manager again.

## Files

| File | Purpose |
|---|---|
| `Detect-WinHttpAutoProxy.ps1` | Reads StartMode and State of `WinHttpAutoProxySvc` and checks whether `WcmSvc` lists it in `DependOnService`. Exits 1 when the service is disabled with an active dependency or the connection manager is stopped. |
| `Remediate-WinHttpAutoProxy.ps1` | Exports the service key, sets the start type to Manual, starts the service and `WcmSvc`, then reads both services back. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-WinHttpAutoProxy.ps1` as the detection script and `Remediate-WinHttpAutoProxy.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, then widen the scope.

## Notes

- Low impact: the start type goes back to Manual and `WcmSvc` is started. No restart and no sign-out.
- The script only changes devices where `WcmSvc` actually depends on the service. Older builds without the dependency are reported as NotApplicable.
- Keep WPAD discovery off with the `DisableWpad` value under `Internet Settings\WinHttp`. That value does not need the service to be disabled.
- If a GPO or RMM tool sets the service start type, set `$ManagedByPolicy = $true` so the script only reports.
- Logs: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT_WinHttpAutoProxy.log`.
