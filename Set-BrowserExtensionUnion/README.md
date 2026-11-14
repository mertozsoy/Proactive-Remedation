# Set Browser Extension Union

Overlapping Edge or Chrome force-install profiles can leave required extensions missing. These scripts merge administrator-selected group lists and append missing machine policy entries while preserving existing entries.

## Files

| File | Purpose |
|---|---|
| `Detect-BrowserExtensionUnion.ps1` | Builds the required union and checks machine force-install lists for missing entries and conflicting update URLs. |
| `Remediate-BrowserExtensionUnion.ps1` | Backs up existing lists, adds missing numbered REG_SZ values and verifies the required union. |

## Deployment (Intune)

1. Set identical `$ExtensionGroups` in both scripts. Each object has `Browser = 'Edge'` or `Browser = 'Chrome'` and `Entries = @('extension_id;https_update_url')`. Add one object per source group. Use approved 32-letter IDs from a through p. An ID alone selects that browser's default store.
2. Build a separate combined configuration for each distinct device cohort. Include only lists approved for that cohort. Assign one configuration per device using mutually exclusive device groups or exclusions.
3. Withdraw other Intune, GPO and browser cloud policies that write these lists. Review effective browser policies, including user policies. After confirming exclusive ownership, set `$PolicyOwnershipConfirmed = $true` in both scripts.
4. Go to **Devices > Scripts and remediations > Remediations > Create**. Upload the detection and remediation files.
5. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
6. Assign to a pilot device group first. Schedule daily and verify effective policy and extension installation in each browser before expanding.

## Notes

- Group membership is not queried. Empty lists return `NotApplicable`; unconfirmed ownership blocks missing-entry remediation.
- Only HKLM machine policy is merged. Every browser user on the device receives it; user-specific targeting and cloud-policy precedence are outside scope.
- Existing values are preserved. Conflicting URLs, malformed entries or a machine `ExtensionSettings` value block changes; HTTPS update URLs are required.
- Existing lists are exported to `%ProgramData%\IntuneRemediations\Backup` before changes. No entries are deleted; removing a configured ID does not remove its policy entry.
- Success verifies registry state, not download or installation. Review `edge://policy` or `chrome://policy` and installed extensions; offline stores and other policy sources can still prevent installation.
