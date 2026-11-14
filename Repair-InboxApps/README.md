# Repair Inbox Apps

Intune Remediations script pair. On some Windows 11 devices Notepad, Snipping Tool, Calculator or Microsoft Store is present on the device but not registered for the user, so the app does not open or is not listed. This pair finds those apps per user and registers them again.

## Files

| File | Purpose |
|---|---|
| `Detect-InboxApps.ps1` | Checks each package family in `$InboxApps` for the signed-in user. An app counts as missing only when it is staged on the device (`AppxAllUserStore\Applications`) and was not deprovisioned by an admin. |
| `Remediate-InboxApps.ps1` | Runs `Add-AppxPackage -RegisterByFamilyName` for each missing app and checks the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-InboxApps.ps1` as the detection script and `Remediate-InboxApps.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Runs in the user context. No admin rights are needed to register a staged app.
- Apps that were removed on purpose (listed under `AppxAllUserStore\Deprovisioned`) are reported as skipped and are not restored.
- Apps that are not staged on the device at all are reported as `NotStaged`. Those need a Store or Intune app deployment, this script does not download anything.
- On Windows 10 Notepad is not a Store app and shows up as `NotStaged`.
