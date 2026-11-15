# Repair Https Protocol Association

Windows shows the message You need a new app to open this https link when the handler behind the http or https association is missing or broken. The detection script resolves the per-user association and checks that the handler executable exists. The remediation script re-registers the Microsoft Edge app package for the user and can reset a broken association after backing up the registry key.

## Files

| File | Purpose |
|---|---|
| Detect-HttpsProtocolAssociation.ps1 | Reads the UserChoice entry for http and https, resolves the ProgId command and reports a handler that no longer exists. |
| Remediate-HttpsProtocolAssociation.ps1 | Re-registers the Edge app package, optionally removes a broken UserChoice entry after a backup and refreshes the shell. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations > Create**.
2. Upload the detection and remediation scripts.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Leave ResetInvalidUserChoice set to false on the first rollout. Enable it only on devices where the handler itself is healthy and the user association is stale.
5. Assign to a pilot group first. A daily schedule is enough.

## Notes

- Only the signed-in user's protocol entries are touched. Machine policy and other user profiles are never changed.
- The remediation script never writes a UserChoice hash. When ResetInvalidUserChoice is enabled it removes a broken entry after a .reg backup so Windows can rebuild the association.
- Removing the entry is opt-in because it clears a user preference. With the default value the script only re-registers Edge and reports the rest.
- Edge is re-registered from the AppxManifest of the installed package. Nothing is downloaded and no command output text is parsed.
- Log and backup files stay under %LOCALAPPDATA%\IntuneRemediations.
