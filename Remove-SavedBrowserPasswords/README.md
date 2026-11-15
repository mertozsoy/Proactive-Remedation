# Remove Saved Browser Passwords

Company password managers replace browser password stores, but Edge and Chrome keep the logins users saved before the rollout. These scripts count the saved logins in every browser profile of the signed-in user and remove the password store after review.

## Files

| File | Purpose |
|---|---|
| `Detect-SavedBrowserPasswords.ps1` | Finds `Login Data` and `Login Data For Account` in the Default and Profile-number folders of Edge and Chrome, then counts saved logins with the SQLite library that ships with Windows. |
| `Remediate-SavedBrowserPasswords.ps1` | Copies each password store to a backup folder, deletes it and verifies that no saved login is left. Deletion is disabled by default. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Upload `Detect-SavedBrowserPasswords.ps1` as the detection script and `Remediate-SavedBrowserPasswords.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Schedule: Daily. Detection reads the profile of the signed-in user, so the user has to be logged on.
5. Set `$DeleteSavedPasswords = $true` only after the pilot report matches the expected users.

## Notes

- Deletion is off by default. ReportOnly exits 1 and lists the counts, so the first runs change nothing.
- Backup copies stay in the user profile under `AppData\Local\IntuneRemediations\Backup\SavedBrowserPasswords`.
- Set the Edge and Chrome `PasswordManagerEnabled` policy to false first. With browser sync on, deleted passwords can come back from the account.
- Vaults of browsers that are running are skipped. The next run picks them up after the user closes the browser.
- Only the password store is removed. History, cookies, bookmarks and autofill data are not touched.
