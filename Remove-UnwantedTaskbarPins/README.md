# Remove Unwanted Taskbar Pins

Microsoft Store and Copilot can remain pinned on existing user taskbars. These scripts check the signed-in user's AppsFolder items and invoke their actual unpin verb, then verify the result.

## Files

| File | Purpose |
|---|---|
| `Detect-UnwantedTaskbarPins.ps1` | Reports installed targets as pinned, unpinned or indeterminate. Missing apps are healthy. |
| `Remediate-UnwantedTaskbarPins.ps1` | Calls the matching AppsFolder verb's DoIt method and checks fresh verbs for up to ten attempts. |

## Deployment (Intune)

1. Open **Devices > Scripts and remediations > Remediations > Create**.
2. Upload the detection and remediation scripts shown above.
3. Run this script using the logged-on credentials: **Yes**.
4. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**, unless you sign both files.
5. Exclude users with managed taskbar layouts or pin restrictions. Assign to a pilot group first and schedule daily.

## Notes

- Keep `$UnwantedApps` identical in both scripts. Only Microsoft Store and the Microsoft.Copilot app are targeted, not legacy Copilot buttons or web shortcuts.
- Known English, Turkish, German, French and Spanish labels are matched after removing menu accelerators. Extend both label lists together for other languages.
- Shell verb availability varies by Windows build. Missing items or unrecognized verbs fail without changes; no unsupported registry fallback is used.
- Policy discovery is not automatic. Exclude managed layouts or set `$TaskbarPinsManagedByPolicy = $true` in both scripts to skip them.
- No app uninstall, layout edits or Explorer restart. An open app can remain visible until closed; rollback is manual repinning.
