# Remediate BitLocker Protection

Intune Remediations script pair. Two BitLocker problems come up again and again: protection left suspended after a BIOS update, and recovery keys that never reached Entra ID. This pair checks both on the OS drive and fixes them without ever lowering protection.

## Files

| File | Purpose |
|---|---|
| `Detect-BitLockerProtection.ps1` | Checks protection status, the recovery password protector and proof that the key was backed up to Entra ID. A drive suspended with a reboot count of 0 is reported, and becomes fixable only when `$AutoResume` is turned on. |
| `Remediate-BitLockerProtection.ps1` | Adds a recovery password protector when missing and backs up every recovery password with `BackupToAAD-BitLockerKeyProtector`. Resuming protection is OFF by default. When `$AutoResume` is on, the drive is resumed only after it stayed suspended through two restarts and 72 hours and no Secure Boot update is pending. The recovery password is never written to output or logs. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-BitLockerProtection.ps1` as the detection script and `Remediate-BitLockerProtection.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Firmware tools often suspend BitLocker with a reboot count of 0, which means suspended forever. That is the main case this package is built for.
- Thresholds: `$MinRebootsSinceFirstSeen`, `$MinSuspendedHours`, `$ReEscrowAfterDays`.
- Log: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT-REM-003.log`
