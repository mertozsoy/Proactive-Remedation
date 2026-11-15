# Remediate Security Log Full

The Security channel is often left in Do not overwrite mode. When the log fills up, audit events can no longer be written, CrashOnAuditFail can block non-admin logons and the device looks unusable until someone clears the log by hand. These scripts find that state and switch the channel back to circular logging.

## Files

| File | Purpose |
|---|---|
| `Detect-SecurityLogFull.ps1` | Reads the Security channel mode, fill level and the CrashOnAuditFail value. Exits 1 when the channel is set to Retain or a CrashOnAuditFail value of 2 blocks non-admin logons. |
| `Remediate-SecurityLogFull.ps1` | Sets the channel to Circular, verifies the mode and resets a CrashOnAuditFail value of 2 to 1. A Retention value set by policy is reported and left alone. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-SecurityLogFull.ps1` as the detection script and `Remediate-SecurityLogFull.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Enforce script signature check: **No**, unless both scripts are signed with a trusted certificate.
5. Assign to a pilot device group first, check the output, then widen the scope. Daily is enough.

## Notes

- Circular logging overwrites the oldest events when the log is full. Keep event forwarding or a larger log size if retention is a requirement.
- A `Retention` value under the EventLog Security policy is treated as managed. The script reports the conflict and does not change the policy value.
- `$ClearLog` is off by default. Turn it on only when the events already in the log are not needed.
- `$RecoverCrashOnAuditFail` resets a value of 2 to 1 after the log can grow again. Windows applies this value after the next restart. The script never restarts the device or the event log service.
- The log file is written to `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT_SecurityLogFull.log`.
