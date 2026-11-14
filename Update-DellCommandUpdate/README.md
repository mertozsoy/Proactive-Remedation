# Update Dell Command Update

Dell driver and BIOS updates can remain unapplied while devices develop dock, Wi-Fi or display issues. These scripts use an installed Dell Command Update 5.x CLI to scan and apply updates, then scan again to verify the result.

## Files

| File | Purpose |
|---|---|
| `Detect-DellCommandUpdate.ps1` | Validates the CLI signature and version, then scans the selected update types. |
| `Remediate-DellCommandUpdate.ps1` | Applies drivers and firmware first, optionally applies BIOS updates, then verifies with fresh scans. |

## Deployment (Intune)

1. Deploy Dell Command Update 5.x first. Use an approved catalog and coordinate with other driver management policies.
2. Go to **Devices > Manage devices > Scripts and remediations > Remediations > Create**.
3. Upload the detection and remediation files. Keep `$AllowBiosUpdates` identical in both.
4. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a Dell pilot device group and schedule daily during a maintenance window.

## Notes

- BIOS updates default to disabled. Set `$AllowBiosUpdates = $true` in both scripts after pilot approval; connect AC power and confirm recovery key escrow first.
- BIOS apply uses `-autoSuspendBitLocker=enable -reboot=disable`. Encrypted devices are supported; DCU temporarily suspends BitLocker until the next restart. No decryption is required.
- Drivers and firmware run first. DCU ignores type filters for Dell Docking Solution updates; include docks in pilot testing. Existing catalog and severity settings remain in effect.
- Scan code 500 means no applicable updates. Codes 1 and 5 return `PendingReboot` with exit 1; BIOS waits if the earlier step needs a restart. The script never requests a reboot.
- Missing or untrusted DCU, unsupported versions and failed scans return exit 1. BIOS passwords and managed DCU settings are not changed; use your approved password provisioning workflow where required.
