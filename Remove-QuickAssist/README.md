# Remove Quick Assist

Quick Assist can remain installed on devices where remote support must use an approved tool. These scripts detect and remove the Store app for all users, its provisioning and the legacy Windows capability.

## Files

| File | Purpose |
|---|---|
| `Detect-QuickAssist.ps1` | Checks all-user Appx registrations, provisioning and the legacy capability. Exits 1 when present. |
| `Remediate-QuickAssist.ps1` | Removes Quick Assist through Appx and DISM cmdlets, then verifies absence. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-QuickAssist.ps1` and `Remediate-QuickAssist.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Assign only to Windows 10/11 devices where Quick Assist is prohibited. Exclude approved support exceptions and remove conflicting Required app assignments first.
5. Start with a pilot group. Schedule daily and review device status before expanding.

## Notes

- `$QuickAssistForbidden = $true` is an administrator scope decision, not automatic policy discovery; keep it identical in both scripts.
- Running Quick Assist defers removal by default; retry after the user closes it.
- Removal is not a permanent install block. Use application control to prevent reinstallation.
- No policy or firewall changes are made. Blocking the shared service endpoint can also break Remote Help.
- Legacy servicing may require a restart; pending states return exit 1 without restarting Windows. Uninstalling can remove Quick Assist app data.
