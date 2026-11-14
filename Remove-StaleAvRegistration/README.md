# Remove Stale AV Registration

Windows Security Center keeps a registration for every antivirus product that registers on a device. When a third-party product is removed badly the registration stays behind and Defender stays passive. This pair lists the registrations that point to a missing product executable and can remove them after a registry backup.

## Files

| File | Purpose |
|---|---|
| `Detect-StaleAvRegistration.ps1` | Reads the `AntiVirusProduct` class in `root/SecurityCenter2`, expands `pathToSignedProductExe` and flags entries whose file no longer exists. Also reports `AMRunningMode`, real-time protection and `ForceDefenderPassiveMode`. |
| `Remediate-StaleAvRegistration.ps1` | Matches each stale entry to its provider key under `HKLM\SOFTWARE\Microsoft\Security Center\Provider\Av`, exports a backup to `%ProgramData%\IntuneRemediations\Backup` and removes the key. The delete runs only when `$RemoveStaleRegistration` is set to `$true`. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-StaleAvRegistration.ps1` as the detection script and `Remediate-StaleAvRegistration.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Report mode by default. The Security Center provider key layout is not documented on Microsoft Learn, so the delete step is behind `$RemoveStaleRegistration`. With the switch at `$false` the script only lists the stale names.
- Provider subkeys are named after the product GUID that Security Center reports for the same product. The script matches on that GUID first and falls back to the registry `DisplayName`, because the two names can differ. Only entries whose recorded executable is missing are touched. A product that is installed and running is never removed. Defender and other Microsoft entries are excluded by name and by path.
- When `ForceDefenderPassiveMode` is set to 1 under `HKLM\SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection` the script exits 0 and does not fight the policy.
- A backup of the provider key is written before the first delete. Restore it by importing the `.reg` file on the device.
- No reboot and no service restart. Defender mode changes on the next Security Center refresh or at the next restart.
- Medium impact: start on a pilot group and keep the backup files until the device reports a Normal Defender mode.
