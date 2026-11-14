# Set Outlook Compose Font

Classic Outlook can retain different compose fonts after a GPO migration. These scripts compare and restore the current user's new-message and reply font values against an approved reference.

## Files

| File | Purpose |
|---|---|
| `Detect-OutlookComposeFont.ps1` | Checks four binary font values and reports drift. |
| `Remediate-OutlookComposeFont.ps1` | Writes the reference values when Outlook is closed and verifies them. |

## Deployment (Intune)

1. On a reference user profile with the same classic Outlook version, set the approved font for new messages and replies under **File > Options > Mail > Stationery and Fonts**. Close Outlook.
2. Read `ComposeFontSimple`, `ComposeFontComplex`, `ReplyFontSimple` and `ReplyFontComplex` from `HKCU\Software\Microsoft\Office\16.0\Common\MailSettings`. Convert each binary value to comma-separated two-digit hexadecimal bytes. Paste the four strings into `$ExpectedFontHex` in both scripts. Set `$ExpectedFontLabel` to match. The initial label is an example, not an embedded font definition.
3. Go to **Devices > Scripts and remediations > Remediations > Create**. Upload the detection and remediation scripts.
4. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** unless signed for your environment.
5. Assign to a pilot user group. Schedule daily when Outlook is usually closed. Check new messages and replies in the pilot before wider deployment.

## Notes

- Reference values are required; empty or malformed hex fails without changing font settings. Keep both scripts identical.
- Only initialized classic Outlook 16.0 profiles are targeted. New Outlook, signatures, themes and plain-text fonts are unchanged.
- MailSettings policy keys cause exclusion. Exclude other active GPO/Intune font assignments or set `$ExternallyManaged = $true`; registry checks cannot identify every preference writer.
- Open Outlook defers the repair with exit 1. No process is stopped; changes apply at the next Outlook start.
- Binary values are compared exactly. This restores defaults, not formatting already present in a message; rollback uses a reference of the previous defaults.
