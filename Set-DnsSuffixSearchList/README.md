# Set DNS Suffix Search List

Intune Remediations script pair. A Microsoft Entra joined device does not get a primary DNS suffix from Active Directory. Short names such as a file server, an RDP host or a DFS namespace do not resolve. This pair checks the global DNS suffix search list and adds the suffixes you define.

## Files

| File | Purpose |
|---|---|
| `Detect-DnsSuffixSearchList.ps1` | Reads the global suffix search list and compares it with `$ExpectedSuffixes`. Exits 1 if a suffix is missing. Skips domain-joined devices and devices where the DNS client policy key exists. |
| `Remediate-DnsSuffixSearchList.ps1` | Merges the missing suffixes into the existing list, flushes the DNS cache and verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-DnsSuffixSearchList.ps1` as the detection script and `Remediate-DnsSuffixSearchList.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first and check the output before you widen the scope.

## Notes

- `$ExpectedSuffixes` is empty by default and the pair returns NotApplicable. Set your own DNS suffixes in both scripts before deployment.
- The script only adds suffixes. It does not remove suffixes that already exist on the device.
- A global suffix search list replaces primary suffix and devolution for unqualified queries. Keep the list short and put the most used suffix first.
- Domain-joined devices and devices with the DNS client policy key under `HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient` are skipped so the script does not fight Group Policy.
- No restart is needed. The DNS cache is flushed after the change and new queries pick up the list.
