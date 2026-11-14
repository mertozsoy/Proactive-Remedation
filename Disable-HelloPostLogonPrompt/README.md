# Disable Hello Post Logon Prompt

Intune Remediations script pair. Users get a Windows Hello for Business PIN setup screen after sign-in that they cannot skip, even though nobody asked for it. This pair turns off provisioning after sign-in on devices where no MDM policy manages Windows Hello for Business. Hello stays available in Settings.

## Files

| File | Purpose |
|---|---|
| `Detect-HelloPostLogonPrompt.ps1` | Reads the MDM policy (`HKLM\SOFTWARE\Microsoft\Policies\PassportForWork\<TenantId>\Device\Policies`) and the Group Policy key (`HKLM\SOFTWARE\Policies\Microsoft\PassportForWork`). Flags the device when `DisablePostLogonProvisioning` is not 1 and Hello is not disabled. |
| `Remediate-HelloPostLogonPrompt.ps1` | Writes `DisablePostLogonProvisioning=1` to the Group Policy key. Writes `Enabled=1` only when the value is missing. Reads the values back. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-HelloPostLogonPrompt.ps1` as the detection script and `Remediate-HelloPostLogonPrompt.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- If an MDM policy for Windows Hello for Business exists on the device, the scripts report `ManagedByMDM` and change nothing. Fix the Intune policy instead.
- An existing `Enabled` value (0 or 1) is never changed. The script does not turn Windows Hello for Business off or on.
- Domain joined devices without an `Enabled` value are skipped (`$SkipDomainJoinedWithoutPolicy`), because writing `Enabled=1` there would turn Hello on.
- `DisablePostLogonProvisioning` needs Windows 11 22H2 with KB5035942 or Windows 10 with build 19041.4239 or later.
- The prompt also comes from the tenant wide setting under Devices > Enrollment > Windows Hello for Business. Check that first.
