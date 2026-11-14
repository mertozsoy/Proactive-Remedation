# Repair GlobalProtect Settings

GlobalProtect can lose its default portal address or pre-logon bootstrap value. These scripts compare PanSetup values with an approved baseline and repair mismatches without restarting the VPN service.

## Files

| File | Purpose |
|---|---|
| `Detect-GlobalProtectSettings.ps1` | Checks the portal and optional Prelogon value, including REG_SZ type. |
| `Remediate-GlobalProtectSettings.ps1` | Backs up existing PanSetup settings, repairs mismatches and verifies the stored values. |

## Deployment (Intune)

1. Set `$ExpectedPortal` to your approved hostname or IP in both scripts. Do not include a URL scheme, port or path.
2. Confirm no Intune profile, GPO, installer or other tool manages these same values. Then set `$LocalSettingsOwnershipConfirmed = $true` in both scripts.
3. Go to **Devices > Manage devices > Scripts and remediations > Create script package**. Upload both scripts.
4. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot device group and schedule daily. Expand after verifying the client configuration and connection.

## Notes

- `$RepairPrelogon = $false` leaves Prelogon untouched; enable it in both scripts only after approving pre-logon and machine certificate prerequisites. The supported target is string `1`.
- Ownership cannot be inferred from these registry values; unconfirmed ownership blocks repairs. Keep both scripts' settings identical.
- Only HKLM PanSetup bootstrap values are repaired; downloaded portal configuration and user portal selections are untouched.
- Existing settings are exported to `%ProgramData%\IntuneRemediations\Backup` before repair. Keep backups restricted to administrators and SYSTEM.
- No reconnect, restart or certificate change occurs. Success verifies stored values only; confirm the tunnel separately after the client next reads settings.
