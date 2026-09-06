# Report Device Uptime

Intune Proactive Remediation pair used purely for **inventory/reporting** of device uptime since last reboot. It does not change anything on the device.

## Files

| File | Purpose |
|---|---|
| `Detect-DeviceUptime.ps1` | Reads `Win32_OperatingSystem.LastBootUpTime`, calculates elapsed uptime, and writes a single-line `DeviceName=...; Uptime=D:HH:MM:SS` string to stdout. Always exits `0`. |
| `Remediate-DeviceUptime.ps1` | No-op stub required by the Proactive Remediation model. Always exits `0`. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context**.
4. Review the **Detection script output** column in Intune reporting to see uptime per device.

## Notes

- No environment-specific values are present in these scripts.
- Since detection always exits `0`, this remediation never shows as "non-compliant" — it's designed only to surface data in reports.
