# Remediate Hybrid Join State

Intune Remediations script pair. Hybrid devices that never finish the Entra join are blocked by Conditional Access and never get a PRT. This pair finds them from the device side.

## Files

| File | Purpose |
|---|---|
| `Detect-HybridJoinState.ps1` | Parses `dsregcmd /status` and flags domain joined devices that are not Entra joined, a DeviceAuthStatus other than SUCCESS, and the AzureAdJoined plus WorkplaceJoined dual state. |
| `Remediate-HybridJoinState.ps1` | Starts the Automatic-Device-Join task. `dsregcmd /leave` on authentication failure is OFF by default (`$AllowLeaveOnAuthFailure`). Dual state is only reported; the BlockAADWorkplaceJoin policy is the right fix for it. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-HybridJoinState.ps1` as the detection script and `Remediate-HybridJoinState.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- The join only completes after Entra Connect has synced the computer object.
