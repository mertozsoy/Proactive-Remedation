# Repair ConfigMgr Client Health

Co-managed devices keep the Configuration Manager client next to the Intune management agent. When the SMS Agent Host service stops or the `root\ccm` WMI provider stops answering, software updates and other ConfigMgr workloads fail while the device still looks enrolled. This pair checks the client on every run and repairs it in place.

## Files

| File | Purpose |
|---|---|
| `Detect-ConfigMgrClientHealth.ps1` | Checks the CcmExec service state and start mode, queries `SMS_Client` in `root\ccm` and reads the assigned site with `GetAssignedSite`. Exits 1 when the client is stopped, disabled, unresponsive or unassigned. |
| `Remediate-ConfigMgrClientHealth.ps1` | Sets the service to Automatic when it is disabled or manual, starts it, restarts it once when the provider does not answer and sends a machine policy request. Verifies the service, the provider and the site code afterwards. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-ConfigMgrClientHealth.ps1` as the detection script and `Remediate-ConfigMgrClientHealth.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group of co-managed devices first, check the output, then widen the scope.

## Notes

- Medium impact: the script restarts the SMS Agent Host service when the WMI provider does not answer. Set `$RestartAgentHost = $false` if a deployment is running on the target devices.
- A full client reinstall with `ccmsetup.exe /forceinstall` is off by default. Set `$EnableClientReinstall = $true` only for devices where the service or provider stays broken.
- The script skips devices while `ccmsetup.exe` is running and never restarts the device.
- A client with no assigned site needs a boundary or site assignment review. The script only sends a policy request.
- Devices without a ConfigMgr client are reported as not applicable.
