# Enable Application Identity

AppLocker cannot enforce rules while Application Identity is stopped. These scripts detect a stopped AppIDSvc service, start it and verify that it is running.

## Files

| File | Purpose |
|---|---|
| Detect-ApplicationIdentity.ps1 | Checks service state and flags Disabled startup configuration. |
| Remediate-ApplicationIdentity.ps1 | Starts the service and waits for Running without changing startup configuration. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload Detect-ApplicationIdentity.ps1 and Remediate-ApplicationIdentity.ps1 in their respective fields.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
4. Assign only to devices intended to use AppLocker. Test the existing rules in audit mode first.
5. Start with a pilot group and schedule hourly.

## Notes

- Starting the service can activate existing enforced AppLocker rules. Validate application access first.
- Disabled startup is reported with exit 1. Correct the owning service policy or approved configuration centrally.
- Startup type and AppLocker rules are unchanged. Configure automatic startup centrally for persistence after restart.
- Running confirms service health only, not rule deployment or enforcement. Missing service returns NotApplicable.
- WaitSeconds defaults to 30 per transition. Logs use %ProgramData%\Microsoft\IntuneManagementExtension\Logs\IRT_ApplicationIdentity.log.
