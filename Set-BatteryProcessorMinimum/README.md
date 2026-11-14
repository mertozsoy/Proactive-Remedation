# Set Battery Processor Minimum

Some laptops feel slow after unplugging. This script pair raises the active power plan's minimum processor state on battery to a configurable floor and verifies the saved value. It does not diagnose CPU performance or change plugged-in settings.

## Files

| File | Purpose |
|---|---|
| `Detect-BatteryProcessorMinimum.ps1` | Checks mobile hardware, battery presence, power policy overrides and the active plan's DC minimum. |
| `Remediate-BatteryProcessorMinimum.ps1` | Raises a lower DC minimum with powercfg, reapplies the same plan and verifies the result. |

## Deployment (Intune)

1. Set `$MinimumProcessorPercent` identically in both scripts. The starting value is 20 percent, not a Microsoft recommendation.
2. Go to **Devices > Manage devices > Scripts and remediations > Create script package**.
3. Upload the detection and remediation scripts.
4. Run this script using the logged-on credentials: **No**. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to an affected laptop pilot group and schedule daily. Compare responsiveness and battery life before widening the scope.

## Notes

- Five percent can be normal. A higher minimum may increase battery drain, heat and fan noise.
- Only the active base plan and PROCTHROTTLEMIN are changed. Higher values, AC settings, maximum state, efficiency-class-1 settings and power-mode overlays are untouched.
- PolicyManaged means Windows reports a power policy override; no change is made. Exclude devices whose power settings are controlled by other management tools.
- Non-mobile devices or devices without a reported battery are NotApplicable. A maximum below the floor is Blocked; API failures exit 1.
- The previous value and scheme GUID are logged. For rollback, remove the assignment and restore that plan's original DC minimum with powercfg, then reapply the plan.
