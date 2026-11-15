# Remove Stale VPN Connections

Detection and remediation script pair for Intune Remediations. Users collect more than one entry for the same VPN, or keep entries for a gateway that was replaced. Windows keeps all of them in the user phone book, so the VPN list in Settings offers every old entry. This pair finds those entries and removes them, keeping one working connection per name.

## Files

| File | Purpose |
|---|---|
| `Detect-StaleVpnConnections.ps1` | Runs as the user. Reads the connections in the user phone book with `Get-VpnConnection`. Flags names from `$ObsoleteNames`, connections that point to `$ObsoleteServerAddresses`, and entries whose name is a copy of another existing entry. Exits 1 when something can be removed. |
| `Remediate-StaleVpnConnections.ps1` | Backs up `rasphone.pbk`, removes the flagged entries with `Remove-VpnConnection`, then reads the phone book again. A connection that is currently connected is left alone. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-StaleVpnConnections.ps1` as the detection script and `Remediate-StaleVpnConnections.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Fill `$ObsoleteNames` or `$ObsoleteServerAddresses` in both scripts and keep the lists identical. Empty lists leave only duplicate name detection active.
- A name is treated as a copy only when the suffix (for example ` (2)` or ` - Copy`) is removed and the base name exists as another connection. A profile that ends with a number for another reason is not touched.
- `$ProtectedNames` skips entries that must never be removed, such as an Always On VPN profile.
- A connection in `Connected` state is reported as skipped instead of being disconnected. It is handled on a later run.
- The phone book file is copied to `%LOCALAPPDATA%\IntuneRemediations\Backup` before the first removal.
