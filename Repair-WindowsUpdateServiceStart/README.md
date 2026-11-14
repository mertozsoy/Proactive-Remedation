# Repair Windows Update Service Start

Disabled Windows Update services prevent update activity even when update policies are assigned. These scripts detect disabled or missing wuauserv, UsoSvc, BITS and WaaSMedicSvc services and restore disabled services through Service Control Manager.

## Files

| File | Purpose |
|---|---|
| `Detect-WindowsUpdateServiceStart.ps1` | Checks startup modes without requiring services to remain running. |
| `Remediate-WindowsUpdateServiceStart.ps1` | Repairs disabled startup modes and verifies the result. Leaves policy-defined services unchanged. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload the detection and remediation scripts shown above.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
4. Review `$RecoveryStartupTypes` against your approved Windows image. Add services controlled by custom MDM scripts, Group Policy Preferences or RMM to `$PolicyManagedServices` and exclude those devices where appropriate.
5. Assign to a pilot device group first. Schedule daily.

## Notes

- Recovery uses Manual for all four disabled services; this is not a factory-default reset for every Windows build. Enabled Automatic or Manual modes are preserved, including dynamic BITS behavior.
- Merged local/domain security policy service entries are excluded. Policy export failure blocks changes; custom script and preference ownership requires the explicit exclusion list.
- Protected service access failures remain failed. No registry, ownership or service ACL bypass is attempted; missing services require Windows repair.
- Targets Windows 10 1809 and later client systems. Does not start or stop services, clear update caches, trigger scans or restart Windows.
- Success confirms startup availability only, not update installation. Logs: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT_WindowsUpdateServiceStart.log`.
