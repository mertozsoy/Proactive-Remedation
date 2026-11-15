# Disable WPAD

Disables WinHTTP proxy auto-discovery by setting the machine DisableWpad value to DWORD 1. The scripts leave WinHttpAutoProxySvc and explicit proxy settings unchanged.

## Files

| File | Purpose |
|---|---|
| `Detect-Wpad.ps1` | Checks the native DisableWpad value and its registry type. |
| `Remediate-Wpad.ps1` | Creates the missing value and verifies it. Approved replacement of an existing value includes a registry backup. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-Wpad.ps1` and `Remediate-Wpad.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **No**.
4. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot device group with direct connectivity or an explicit proxy. Schedule daily.

## Notes

- Requires Windows 10 1809 or later, or Windows Server 2019 or later.
- WinHTTP only; separately disable Automatically detect settings in Windows Settings. Browser settings and direct DNS queries are not covered.
- Exclude devices where GPO or Intune owns this setting, or set `$SettingManagedExternally = $true` in both scripts. Ownership is not inferred from registry data.
- Existing conflicting values are reported as Blocked. Set `$ReplaceExistingValue = $true` only after confirming local ownership; backups use `%ProgramData%\IntuneRemediations\Backup`.
- WPAD-dependent connectivity may fail. Validate proxy requirements first; no service restart or reboot is performed. Healthy verifies configuration, not live traffic.
