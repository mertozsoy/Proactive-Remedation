# Repair Hosts File Baseline

A stale or malicious entry in the local hosts file overrides DNS for the whole device. Users lose access to Microsoft 365 or internal sites and the cause survives reboots. This script pair compares the hosts file with an approved list, backs up the file and rewrites it to the baseline.

## Files

| File | Purpose |
|---|---|
| `Detect-HostsFile.ps1` | Reads active hosts entries and reports any that are not approved or any approved entry that is missing. Loopback entries for localhost are allowed. |
| `Remediate-HostsFile.ps1` | Copies the current file to the backup folder, rewrites it with loopback and approved entries only, then verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-HostsFile.ps1` as the detection script and `Remediate-HostsFile.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- `$EnableRemediation = $false` by default. Fill `$ApprovedEntries` in both scripts before enabling it; with an empty list every non-loopback entry is removed.
- Loopback entries for localhost are kept. Every other entry is removed.
- The current file is copied to `%ProgramData%\IntuneRemediations\Backup` before the rewrite.
- Malware or a security agent that rewrites the file can bring an entry back. The next scheduled run reports it again.
- Find the source of the entry before you widen the scope. A rewritten file only removes the symptom.
