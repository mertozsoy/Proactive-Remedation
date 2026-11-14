# Remove Retired Server Drives

Old drive mappings can remain after a file server is retired. These scripts find exact server matches and remove approved SMB drive mappings from the signed-in user's session and persistent profile.

## Files

| File | Purpose |
|---|---|
| `Detect-RetiredServerDrives.ps1` | Finds SMB drive mappings whose UNC server matches the retirement list. |
| `Remediate-RetiredServerDrives.ps1` | Removes policy-reviewed mappings with UpdateProfile and verifies that none remain. |

## Deployment (Intune)

1. Set `$RetiredServers` in both scripts to retired server names, for example `@('oldfs', 'oldfs.contoso.com')`.
2. Remove the old assignments from GPO, Intune and logon scripts. Add only confirmed unmanaged servers to `$PolicyReviewedServers` in both scripts.
3. Go to **Devices > Scripts and remediations > Remediations > Create**. Upload the detection and remediation scripts.
4. Run this script using the logged-on credentials: **Yes**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot group first. Schedule daily and review the results before widening scope.

## Notes

- Empty retirement lists return NotApplicable. Unreviewed servers are reported but never changed; mapping ownership is not inferred automatically.
- Matching is exact and case-insensitive. List short names, FQDNs and aliases separately; no DNS lookup or reachability test is used.
- Only SMB mappings with drive letters visible in the current user session are included. WebDAV, global mappings and other sessions are outside scope.
- Removing a mapping does not delete share files, but can interrupt open applications. Schedule outside working hours; retained assignments can recreate mappings.
- Logs contain drive letters and counts, not usernames or UNC paths. UpdateProfile removes persistence without direct registry edits.
