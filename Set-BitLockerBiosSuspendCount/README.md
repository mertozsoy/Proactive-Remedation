# Set BitLocker BIOS Suspend Count

A BIOS update can need BitLocker protection suspended until a planned restart. These scripts check the OS volume and restore the approved reboot count during a short maintenance window.

## Files

| File | Purpose |
|---|---|
| `Detect-BitLockerBiosSuspendCount.ps1` | Checks protection and the remaining suspend count before the first maintenance restart. |
| `Remediate-BitLockerBiosSuspendCount.ps1` | Suspends protection with the configured reboot count and verifies both values. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Set matching UTC start/end times and `$RebootCount` in both scripts. Use `yyyy-MM-ddTHH:mm:ssZ`; the window must not exceed four hours.
3. Confirm recovery key escrow and approved exclusions from conflicting protection-resume policies or scripts. Then set `$EnableRemediation = $true` in remediation.
4. Upload the detection and remediation files. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**, unless signed for your environment.
5. Assign only to the BIOS maintenance pilot. Schedule hourly or request an on-demand run before the firmware workflow proceeds. Verify the result before starting that workflow.

## Notes

- Suspension exposes a clear key on disk. `$EnableRemediation` defaults to `$false`; disabled remediation returns failure for unresolved drift.
- Default count is one restart; select 1 to 15 for the vendor workflow. Zero and indefinite suspension are rejected.
- No action occurs after the first restart within the window. Window expiry stops enforcement but does not resume protection; the firmware workflow must restart or safely resume after completion.
- Exclude conflicting management first. Intune sync is not assumed to resume protection universally; this script cannot lock suspension against another writer.
- Only fully encrypted, unlocked OS volumes with TPM and recovery password protectors qualify. Missing count information fails closed; protector presence does not prove escrow.
