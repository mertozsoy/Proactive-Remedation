# Remove Stale Proxy Settings

Retired proxy or PAC settings can prevent applications from reaching their services. These scripts find exact matches in the default WinHTTP configuration and saved WinINET settings, then back up and remove approved leftovers.

## Files

| File | Purpose |
|---|---|
| `Detect-StaleProxySettings.ps1` | Checks the default WinHTTP proxy and saved SYSTEM/loaded user proxy and PAC values against retirement lists. |
| `Remediate-StaleProxySettings.ps1` | Backs up matching settings, resets the default WinHTTP proxy or removes matching saved WinINET values, and verifies the saved state. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Populate `$StaleProxyServers` and `$StalePacUrls` identically in both scripts. Use complete saved strings, including protocol mappings and ports. Empty lists return `NotApplicable`.
3. Upload the detection and remediation scripts. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
4. Review proxy ownership and confirm direct connectivity on a pilot group before setting `$EnableRemediation = $true` in the remediation script.
5. Assign to that pilot group first. Schedule daily and review results before widening the scope.

## Notes

- Only complete matches are removed. Proxy comparisons ignore case; PAC URL comparisons preserve case. Unreachable does not mean retired.
- Remediation starts disabled. Enabling it confirms that matching settings are not managed by Intune, GPO, preferences or VPN software; local policy checks alone cannot prove this. Detected proxy policies block changes.
- WinINET coverage is saved SYSTEM and loaded user values only. Offline profiles, machine-wide WinINET, connection binaries, WPAD, VPN-specific settings and advanced WinHTTP PAC settings are outside scope.
- Registry exports are stored under `%ProgramData%\IntuneRemediations\Backup\StaleProxySettings_<id>`, restricted to SYSTEM and Administrators. Restore only the required values after reviewing the backup.
- `Fixed` confirms saved settings, not service connectivity or running application caches. Reopen affected applications as needed; no service restart, reboot or sign-out is performed.
