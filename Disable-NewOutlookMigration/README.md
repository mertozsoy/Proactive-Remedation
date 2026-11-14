# Disable New Outlook Migration

Classic Outlook may still show the new Outlook toggle or start an unwanted migration. These scripts hide the toggle and disable admin-controlled migration and the automatic migration user setting for the signed-in user.

## Files

| File | Purpose |
|---|---|
| `Detect-NewOutlookMigration.ps1` | Checks three DWORD settings and reports drift or conflicting Office policies. |
| `Remediate-NewOutlookMigration.ps1` | Writes missing or incorrect local settings and verifies the result without closing Outlook. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-NewOutlookMigration.ps1` and `Remediate-NewOutlookMigration.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Assign to a pilot user group with classic Outlook. Schedule daily.
5. Confirm the toggle after the user next closes and opens classic Outlook.

## Notes

- Defaults: HideNewOutlookToggle=1 and DoNewOutlookAutoMigration=0 in the user's Outlook Options\General; NewOutlookMigrationUserSetting=0 in the user's Office policy Outlook\Preferences.
- Existing conflicting Group Policy, Intune or cached Cloud Policy values cause Blocked; correct the central assignment first. Policy origin is not inferred from registry values.
- The automatic migration user setting is created only when absent from policy. Access denied returns an error; deploy that setting centrally if required.
- No Outlook user settings means NotApplicable. Registry verification does not prove a particular Outlook build honors every setting.
- Outlook is not closed. These settings do not uninstall new Outlook, revert migrated users or block mailbox access. Removing the assignment does not undo written values.
