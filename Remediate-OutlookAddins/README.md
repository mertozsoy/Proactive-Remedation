# Remediate Outlook Add-ins

Outlook turns off COM add-ins that it thinks slow down startup or shutdown. Business add-ins such as the Teams meeting add-in, a document management client or a classification add-in then disappear from the ribbon and the user calls the service desk. This pair finds the configured add-ins in the per-user registry, turns them back on and adds them to the do-not-disable allow list.

## Files

| File | Purpose |
|---|---|
| `Detect-OutlookAddins.ps1` | Runs as the user. Reads `LoadBehavior` for each critical add-in, the `DisabledItems` list and the `DoNotDisableAddinList` entry. Exits 1 when an add-in is off, listed as disabled or not protected. |
| `Remediate-OutlookAddins.ps1` | Exports the resiliency and add-in keys, sets `LoadBehavior` to 3, removes the matching `DisabledItems` values, writes the allow list entry and verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-OutlookAddins.ps1` as the detection script and `Remediate-OutlookAddins.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily. Assign to a user group, not a device group.
5. Start with a pilot group, check the output, then widen the scope.

## Notes

- All keys are per user. The script must run with the logged-on credentials and cannot fix a user who is not signed in.
- `$CriticalAddins` holds the ProgID list. The default entry is the Teams meeting add-in. Add your own ProgIDs from `HKCU\Software\Microsoft\Office\16.0\Outlook\Addins`.
- Outlook reads the add-in state at start. If Outlook is open the output ends with `Effective=NextOutlookStart`. Nothing is closed or restarted by the script.
- An add-in that consistently crashes Outlook cannot be protected this way. That crash needs to be fixed with the add-in owner.
- The resiliency key and the add-in keys are exported to `%LOCALAPPDATA%\IntuneRemediations\Backup` before the change. Files older than 30 days are removed on the next run.
