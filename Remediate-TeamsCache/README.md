# Remediate Teams Cache

The new Microsoft Teams client can stop loading or loop on the sign-in screen when its local cache is damaged. The cache lives in the user's own AppData folder, so a helpdesk visit is usually needed. This pair measures the cache of the signed-in user, closes Teams and clears the cache when it reaches the threshold.

## Files

| File | Purpose |
|---|---|
| `Detect-TeamsCache.ps1` | Measures files under the new Teams `LocalCache\Microsoft\MSTeams` folder and reports whether `ms-teams` is running. |
| `Remediate-TeamsCache.ps1` | Closes Teams, deletes the cache files, keeps the `logs` folder and verifies the remaining size. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-TeamsCache.ps1` as the detection script and `Remediate-TeamsCache.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Do not set a schedule. Run the script on demand from the device or the user.
5. Assign to a pilot group first, then widen the scope.

## Notes

- The cache path is the one Microsoft documents for the new Teams client. Classic Teams cache is not touched.
- `$StopTeamsProcess = $false` by default: while Teams is open the pair only reports and the cache is cleared at a run when Teams is closed. For an on-demand fix with "Run remediation", set it to `$true`; Teams is then closed and unsent chat text is lost.
- `$MinimumCacheMB` defaults to 300 in both scripts. Keep the values identical.
- `$KeepLogs = $true` leaves the `logs` folder in place for support cases.
- Cookies, settings and signed-in accounts inside the cache are removed. The user signs in again on the next start.
