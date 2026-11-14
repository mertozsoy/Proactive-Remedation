# Enable MDM Sync Tasks

Intune Remediations script pair. Hardening scripts and debloat tools sometimes disable the Task Scheduler service or the EnterpriseMgmt tasks, and the device stops its scheduled MDM sync. This pair turns the service and the disabled tasks back on and starts PushLaunch.

## Files

| File | Purpose |
|---|---|
| `Detect-MDMSyncTasks.ps1` | Checks the `Schedule` service start type and state, finds the Intune enrollment ID and looks for disabled or missing tasks under `\Microsoft\Windows\EnterpriseMgmt\<EnrollmentId>\`. |
| `Remediate-MDMSyncTasks.ps1` | Sets the `Schedule` service to Automatic, enables every disabled task of the enrollment and starts `PushLaunch`. Checks the task states again before it exits. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-MDMSyncTasks.ps1` as the detection script and `Remediate-MDMSyncTasks.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Missing tasks are only reported. The script never re-enrolls the device.
- If `sc.exe` cannot change the start type, the script writes `Start=2` to the registry and reports `RebootRequired=True`.
- Devices without an Intune enrollment return `NotApplicable`.
- Find out what disabled the tasks. If a hardening script keeps doing it, the remediation will run on every cycle.
