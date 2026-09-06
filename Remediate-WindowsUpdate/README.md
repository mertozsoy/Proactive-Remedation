# Remediate Windows Update

Intune Proactive Remediation pair that runs a comprehensive Windows Update repair — the classic "reset Windows Update components" playbook — and captures a SetupDiag diagnostic log for troubleshooting.

## Files

| File | Purpose |
|---|---|
| `Detect-WindowsUpdateDiagnostics.ps1` | Downloads Microsoft's [SetupDiag](https://go.microsoft.com/fwlink/?linkid=870142) tool, runs it to analyze Windows Update/upgrade failure logs, waits up to 15 minutes for output, and prints the first two lines of the diagnostic log to the Intune detection output for quick visibility. |
| `Remediate-WindowsUpdate.ps1` | A 10-step Windows Update reset: clears update-pause policies, stops WU-related services (BITS, wuauserv, cryptsvc, usosvc, WaaSMedicSvc), clears the QMGR download cache, hard-deletes `SoftwareDistribution` and `Catroot2`, resets service ACLs, re-registers ~35 WU/BITS-related DLLs, resets Winsock, restarts the services, kicks off an interactive update scan via `USOClient`, and finally re-runs SetupDiag for a fresh diagnostic log. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context** (required for service control, `Catroot2`/`SoftwareDistribution` deletion, ACL resets, and DLL registration).
4. Requires outbound internet access to `go.microsoft.com` to download SetupDiag.

## Notes

- No environment-specific values are present in these scripts; the only external URL is Microsoft's official SetupDiag download link.
- This is an intrusive repair (service restarts, cache wipes, Winsock reset) — pilot on a test group before wide deployment, and expect a multi-minute runtime (the scan step alone waits 5 minutes).
- The remediation script always exits `0` regardless of individual step outcomes; check the log file for granular success/failure per step.
