# Set Event Log Max Size

Small event logs can overwrite investigation evidence before collection. These scripts compare the configured maximum sizes of Security, four AppLocker channels and PowerShell Operational against minimum limits, then increase undersized logs without clearing events.

## Files

| File | Purpose |
|---|---|
| `Detect-EventLogMaxSize.ps1` | Checks maximum sizes and reports drift, missing channels and Security policy conflicts. |
| `Remediate-EventLogMaxSize.ps1` | Increases undersized logs with the Windows Event Log API and verifies each change. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-EventLogMaxSize.ps1` and `Remediate-EventLogMaxSize.ps1`.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Enforce script signature check: **No**, unless you sign both scripts with a trusted certificate.
5. Assign to a pilot device group and schedule daily. Review results before widening assignments.

## Notes

- Keep both configuration lists identical: Security 256 MB, each AppLocker channel 64 MB, PowerShell Operational 128 MB by default. Larger existing limits are preserved.
- Security MaxSize policy is read in KB. A lower policy blocks that channel; a higher policy becomes its target. Policy values are never changed.
- Other management sources cannot be inferred reliably. Put channels controlled by other policies or scripts in `ExternallyManagedLogs` and exclude conflicting assignments.
- Missing optional channels are counted and skipped; missing Security or read failures return failure. Disabled channels stay disabled. Retention and access permissions are unchanged.
- Size limits do not reserve disk space or guarantee retention time. Allow disk headroom and use central forwarding for evidence retention.
