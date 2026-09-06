# Detect Low EFI System Partition Free Space

Intune Proactive Remediation pair that monitors free space on the **EFI System Partition** (a small, normally invisible partition that can fill up over time with firmware update leftovers) and can automatically clean up known-safe HP firmware update files to reclaim space.

## Files

| File | Purpose |
|---|---|
| `Detect-EFIPartition.ps1` | Temporarily mounts the EFI partition to drive letter `S:` (`mountvol S: /S`), measures total/free space and a folder-by-folder size breakdown (drilling into `EFI\HP` on HP devices), flags low free space (default threshold: 60 MB), unmounts the partition, and logs a full report. Exits `1` if free space is below threshold, `0` if healthy. |
| `Remediate-EFIPartitionCleaner.ps1` | Repeats the same mount/measure process, then if `S:\EFI\HP\DEVFW` exists (leftover HP firmware update payloads), deletes its contents and reports space freed before/after. Always exits `1` after cleanup (by design — see Notes) so the run is visible as "remediated" in Intune reporting rather than "already compliant". |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload `Detect-EFIPartition.ps1` as detection and `Remediate-EFIPartitionCleaner.ps1` as remediation.
3. Run in the **system context** (required for `mountvol` and direct access to the EFI system partition).
4. Safe primarily on **HP devices** — the cleanup step only removes files under `EFI\HP\DEVFW`. On non-HP hardware the cleaner will simply report "DEVFW folder not found" and free 0 MB.

## Notes

- No environment-specific values are present in these scripts.
- **Review the `$MinFreeMB` threshold (default 60 MB) and the `DEVFW` deletion target for your hardware fleet before deploying** — deleting the wrong EFI files can affect firmware update capability. Test on a representative HP device first.
- The remediation script intentionally always exits `1`; adjust this if you want Intune to report success after a cleanup instead.
