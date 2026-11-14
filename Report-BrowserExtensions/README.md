# Report Browser Extensions

Detection only script for Intune Remediations. A blocklist stops new installs, but it does not tell you what is already sitting in user profiles. This script lists the Edge and Chrome extension IDs found in every profile on the device and flags the ones that are not on your approved list.

## Files

| File | Purpose |
|---|---|
| `Detect-BrowserExtensions.ps1` | Walks `Extensions\<ID>` in the `Default` and `Profile *` folders of Edge and Chrome under every local user profile. Compares the IDs with `$ApprovedExtensionIds`. Output lists `Browser:ID(profile count)`; no user names are written. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-BrowserExtensions.ps1` as the detection script. Leave the remediation script empty.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Report only. Deleting extension folders from disk is not a supported way to remove an extension and can leave the browser profile in a bad state. Use `ExtensionInstallBlocklist` / `ExtensionSettings` policy to remove them.
- With an empty `$ApprovedExtensionIds` the script runs in inventory mode and always exits 0. Use that first run to build the approved list.
- Some IDs belong to components that ship with the browser. Add them to the approved list after the inventory run.
- `$MaxListedIds` limits how many IDs go into the output. The full list is in the log file.
- To remove one known extension from all profiles, see `Remove-BrowserExtension`.
