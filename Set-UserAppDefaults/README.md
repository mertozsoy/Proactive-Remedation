# Set User App Defaults

Checks the signed-in user's effective HTTP, HTTPS and MAILTO handlers. Optional user-assisted remediation opens Windows Default apps settings and verifies the user's changes. This is not an unattended default-app setter.

## Files

| File | Purpose |
|---|---|
| Detect-UserAppDefaults.ps1 | Compares effective protocol associations with the expected ProgIDs. |
| Remediate-UserAppDefaults.ps1 | Opens Default apps when enabled and returns success only after all expected associations match. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations > Create**.
2. Upload the detection and remediation scripts.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Configure identical ExpectedDefaults in both scripts. The examples target Edge and classic Outlook; install the intended applications first.
5. Review effective GPO and Intune association policies. Only after confirming none apply, set AssociationPolicyAbsentConfirmed and EnableUserAssistedRemediation to true for a coordinated pilot run with users present.
6. Prefer on-demand assignment during a support window. Avoid recurring prompts that override a user's later preference.

## Notes

- Windows does not support silent per-user default changes; registry hashes and UCPD are never modified.
- Settings launch is disabled by default. Users must select the configured apps for HTTP, HTTPS and MAILTO within 180 seconds.
- Expected ProgIDs vary by application version. Confirm them on a reference device; these scripts do not install or repair applications.
- Policy absence requires administrator confirmation; the script does not infer policy ownership or modify managed values.
- PendingUserAction exits 1. Fixed requires matching effective associations; no persistent enforcement or completion marker is created.
