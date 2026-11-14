# Repair Domain Admins Local Group

Hybrid joined devices receive their local Administrators membership from the LocalUsersAndGroups policy. With the Replace action the group is rewritten from the policy list. When the device cannot reach a domain controller the AD group can drop out of the group and the support team loses local admin rights on that device. This pair checks the membership and adds the configured group back.

## Files

| File | Purpose |
|---|---|
| `Detect-DomainAdminsLocalGroup.ps1` | Reads the local Administrators group by SID `S-1-5-32-544` and looks for `$RequiredGroupName` by SID or by name. Exits 1 when the group is missing or cannot be resolved. |
| `Remediate-DomainAdminsLocalGroup.ps1` | Resolves the group to a SID, adds it with `Add-LocalGroupMember` and verifies the membership afterwards. Set `$EnableRemediation = $false` to report only. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-DomainAdminsLocalGroup.ps1` as the detection script and `Remediate-DomainAdminsLocalGroup.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group of hybrid joined devices first, check the output, then widen the scope.

## Notes

- `$RequiredGroupName` is empty by default and the pair returns NotApplicable. Set it in both scripts to your AD group. Fill `$RequiredGroupSid` as well so the check and the add also work when name resolution fails.
- The policy can remove the group again on the next refresh while the device is offline. Fix the policy or the network path as well, the script only restores the membership.
- A device that is not domain joined and a device without the LocalAccounts module are reported as not applicable.
- The script never removes a member and never changes another group. Only the configured group is added when it is missing, then the membership is read back.
- Adding an AD group to local Administrators is a sensitive change. Keep the pilot group small and review the output before the wider assignment.
