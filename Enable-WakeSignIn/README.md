# Enable Wake Sign-In

Devices can resume from sleep without requiring sign-in when CONSOLELOCK is disabled. These scripts check AC and battery settings on the active power plan and enable sign-in where no policy controls the value.

## Files

| File | Purpose |
|---|---|
| `Detect-WakeSignIn.ps1` | Checks active-plan values and policy overrides for AC and DC. |
| `Remediate-WakeSignIn.ps1` | Enables unmanaged values, reapplies the same plan and verifies the configuration. |

## Deployment (Intune)

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-WakeSignIn.ps1` and `Remediate-WakeSignIn.ps1` in their respective fields.
3. Run this script using the logged-on credentials: **No**.
4. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot device group first. Schedule daily.

## Notes

- Keep `$ExpectedConsoleLock = 1` in both scripts. Only the active plan is checked and changed.
- Policy-controlled values are preserved. `PolicyConflict` requires correcting the originating Intune or GPO setting.
- Closing the lid must actually suspend the device. Lid actions, idle locking and sign-in grace periods are outside scope.
- A successful result verifies configuration, not a physical wake or Windows Hello interaction. Validate those on pilot hardware, including Modern Standby devices.
- No restart or sign-out is performed. Read failures and plan changes return failure instead of a healthy result.
