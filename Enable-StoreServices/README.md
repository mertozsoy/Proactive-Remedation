# Enable Store Services

Hardening can disable the services needed for Microsoft Store app deployment. These scripts find disabled Store services and restore demand start without changing Store access policies.

## Files

| File | Purpose |
|---|---|
| `Detect-StoreServices.ps1` | Checks InstallService, ClipSVC and AppXSvc for disabled or missing services. |
| `Remediate-StoreServices.ps1` | Changes disabled services to Manual, requests an InstallService start after repairs and verifies configuration. |

## Deployment (Intune)

1. Review service ownership in GPO, Intune and hardening tools. Add actively managed services to `$PolicyManagedServices` in both scripts. Target devices with retired local hardening only.
2. Go to **Devices > Scripts and remediations > Remediations > Create**.
3. Upload the detection and remediation files.
4. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot device group and schedule daily.

## Notes

- Policy ownership cannot be inferred from service start mode. Excluded disabled services remain reported and are not changed.
- Manual services may stop when idle. Stopped is not a fault; existing enabled start modes are preserved.
- Protected-service access failures and missing services require administrator review. Permissions and registry values are not bypassed.
- Store access and App Installer policies remain unchanged. No apps are installed or re-registered.
- A successful result verifies service configuration, not application installation. Review app deployment status separately.
