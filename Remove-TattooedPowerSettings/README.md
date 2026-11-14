# Remove Tattooed Power Settings

Intune Remediations script pair. A removed power profile can leave its values under the Power policy key. The power options stay grayed out and users cannot change lid close, sleep or display timeouts. This pair finds those values, backs them up and removes them.

## Files

| File | Purpose |
|---|---|
| `Detect-TattooedPowerSettings.ps1` | Reads the setting keys under `Software\Policies\Microsoft\Power\PowerSettings` and lists the ones that hold `ACSettingIndex` or `DCSettingIndex`. Skips the check when an MDM power policy is still active. |
| `Remediate-TattooedPowerSettings.ps1` | Exports each policy key with `reg.exe` to `%ProgramData%\IntuneRemediations\Backup\TattooedPowerSettings`, deletes the key and checks that no value is left. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-TattooedPowerSettings.ps1` as the detection script and `Remediate-TattooedPowerSettings.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- The script does not touch `Software\Microsoft\PolicyManager`, so an active Intune power policy is never removed. Detection returns 0 and reports `Managed`.
- A domain GPO or local GPO that writes the same Power policy keys looks the same in the registry. Remove the source GPO before you run the remediation.
- `$EnableRemediation = $false` turns the remediation into a report only script.
- Backup files are full key exports. They contain no user data and can be restored with `reg import`.
- The next policy refresh can write the values back. If that happens the source of the policy is still active.
