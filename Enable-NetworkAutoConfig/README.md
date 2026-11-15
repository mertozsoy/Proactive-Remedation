# Enable Network AutoConfig Services

Wi-Fi disappears from the network flyout or wired 802.1X never authenticates when WLAN AutoConfig (WlanSvc) or Wired AutoConfig (dot3svc) is set to Disabled. These scripts read both services and restore the default startup type plus the running state. WlanSvc is skipped on devices without a wireless adapter.

## Files

| File | Purpose |
|---|---|
| `Detect-NetworkAutoConfig.ps1` | Reads the startup mode and state of `dot3svc` and `WlanSvc`. Exits 1 when a service is Disabled or WlanSvc is stopped on a device with a wireless adapter. |
| `Remediate-NetworkAutoConfig.ps1` | Sets `dot3svc` back to Manual and `WlanSvc` back to Automatic, starts the services and verifies the result. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
2. Upload `Detect-NetworkAutoConfig.ps1` as the detection script and `Remediate-NetworkAutoConfig.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
4. Assign to a pilot device group first. Schedule daily.
5. Check the output for devices that return to Disabled after each run and fix the source that changes the service.

## Notes

- Manual is the default start mode for `dot3svc` and Automatic is the default for `WlanSvc` on Windows client.
- Set `$SkipWlanWithoutAdapter = $false` to check WlanSvc on devices without a wireless adapter. The default skips them to avoid false drift on desktops.
- `dot3svc` is only needed for wired 802.1X. A wired network without 802.1X works with the service stopped.
- A hardening baseline or debloat script that sets a service back to Disabled wins on the next refresh. Exclude those devices or remove the source setting.
- The script does not restart the device or sign the user out. Service events are logged under WLAN-AutoConfig and Wired-AutoConfig in Applications and Services Logs.
