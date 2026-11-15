# Enable Microsoft Account Sign-in Assistant

Windows Update stops offering feature updates when the Microsoft Account Sign-in Assistant service (wlidsvc) is disabled. These scripts detect a disabled wlidsvc service and set it back to Manual start. Devices where the service is disabled by an active Intune policy are reported and left untouched.

## Files

| File | Purpose |
|---|---|
| `Detect-Wlidsvc.ps1` | Checks the service start mode and the PolicyManager value. Exits 1 when wlidsvc is disabled without an active policy. |
| `Remediate-Wlidsvc.ps1` | Sets the start mode to Manual, starts the service and verifies that it is running. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Upload `Detect-Wlidsvc.ps1` as the detection script and `Remediate-Wlidsvc.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
4. Assign to a pilot device group first. Schedule daily.
5. Check the **Microsoft Account sign-in assistant** setting in your device restrictions profile before rollout. A policy that sets it to Disabled keeps the service off and the script only reports it.

## Notes

- The script reads the PolicyManager value `AllowMicrosoftAccountSignInAssistant` under the Accounts area. Value 0 means an active policy owns the setting, so the service is left unchanged.
- Manual is the documented default start mode for wlidsvc. An Automatic start mode is not changed.
- The service is started when it is stopped because Windows Update expects wlidsvc to be running. No update scan is triggered and the device is not restarted.
- Feature updates may take one or more update cycles to appear after the service is restored.
- Logs: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT_Wlidsvc.log`.
