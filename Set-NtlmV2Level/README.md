# Set NTLMv2 Level

Reads LmCompatibilityLevel from the LSA registry key on Windows clients and raises it to 5. At level 5 the client sends NTLMv2 responses only and refuses LM and NTLM. Drift is reported before any value is written.

## Files

| File | Purpose |
|---|---|
| `Detect-NtlmV2Level.ps1` | Reads LmCompatibilityLevel and returns 1 when the value is missing, not a DWORD or below 5. |
| `Remediate-NtlmV2Level.ps1` | Saves the current value, sets it to 5 and verifies the write. |

## Deployment (Intune)

1. Check the security baseline and any GPO that manages Network security: LAN Manager authentication level. Remove overlapping assignments or exclude those devices.
2. Go to **Devices > Scripts and remediations > Remediations > Create** and select both scripts.
3. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Assign to a pilot device group and schedule daily.
5. Confirm that legacy file shares, NAS devices and printers still authenticate after the change.

## Notes

- Applies to Windows client devices only. Servers return `NotApplicable`.
- The new level is read at the next restart. The script never restarts the device.
- A security baseline or GPO that sets this value wins at the next policy refresh.
- The previous value is saved as a reg file under `%ProgramData%\IntuneRemediations\Backup`.
- Level 5 refuses NTLMv1. Test legacy appliances before broad assignment.
