# Remove Browser Extension

Intune Remediations script pair. A blocked extension can stay on disk in old Edge and Chrome profiles, and a user level forcelist value can bring it back. This pair finds the listed extension IDs in every profile and removes the leftovers.

## Files

| File | Purpose |
|---|---|
| `Detect-BrowserExtension.ps1` | Checks `Extensions\<ID>` in every Edge and Chrome profile under every local user profile, and the user level `ExtensionInstallForcelist` keys of loaded user hives. Also reports whether the ID is in the machine blocklist or forcelist. |
| `Remediate-BrowserExtension.ps1` | Removes user level forcelist values that point to the ID and deletes the extension folders. Skips a browser that is running when `$SkipWhenBrowserRunning` is `$true` and tries again on the next run. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-BrowserExtension.ps1` as the detection script and `Remediate-BrowserExtension.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Fill `$ExtensionIds` with the 32 character IDs in both scripts. Empty list means NotApplicable.
- Put the same IDs in `ExtensionInstallBlocklist` with an Intune policy. The script does not write machine policy keys. Without the blocklist the browser can install the extension again.
- A machine level forcelist entry wins over the blocklist. The script only reports it; fix it in the policy that sets it.
- User hives that are not loaded (users not signed in) are checked on a later run.
- Edge often keeps running in the background. If deletions stay deferred, set `$SkipWhenBrowserRunning` to `$false` after a pilot.
