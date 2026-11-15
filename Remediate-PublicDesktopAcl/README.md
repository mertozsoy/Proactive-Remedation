# Remediate Public Desktop ACL

Installers drop shortcuts on the Public Desktop and standard users cannot delete them. The folder ACL gives Administrators full control and everyone else read access. This pair checks the ACL and grants the built-in Users group delete rights on the folder contents so users can clean up the icons themselves.

## Files

| File | Purpose |
|---|---|
| `Detect-PublicDesktopAcl.ps1` | Reads the ACL of the Public Desktop folder. Exits 1 when the Users group lacks delete rights on the folder or on its files, or when a deny entry blocks them. |
| `Remediate-PublicDesktopAcl.ps1` | Saves the folder ACL with `icacls /save`, adds the missing delete rights and verifies the result. Write access is not granted. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-PublicDesktopAcl.ps1` as the detection script and `Remediate-PublicDesktopAcl.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Only two rights are added: delete child on the folder and delete on its files. Modify or FullControl on the Public Desktop is not granted unless `$GrantModifyInstead` is set to `$true`.
- Users can then remove any icon on the Public Desktop, including shortcuts that IT deployed on purpose. Tell the service desk before you widen the assignment.
- A deny entry for Users, Everyone or Authenticated Users is reported as Blocked and never removed. Find the policy that sets it.
- Shortcuts with a protected ACL keep failing after the folder change. Set `$EnableShortcutInheritance` to `$true` to let those files inherit again.
- The original ACL is saved under `%ProgramData%\IntuneRemediations\Backup`. To put it back run `icacls C:\Users\Public /restore` with the saved file as the last argument.
