# Repair Primary Refresh Token

A missing primary refresh token (PRT) breaks single sign-on for the signed-in user. Outlook and Teams ask for a password again, and Conditional Access no longer sees the device as trusted. These scripts read the SSO state from `dsregcmd` and schedule a token refresh without a sign-out.

## Files

| File | Purpose |
|---|---|
| `Detect-PrimaryRefreshToken.ps1` | Reads the SSO state for the signed-in user. Reports a problem when `AzureAdPrt` is not YES, when the token is expired, or when the last update is older than `$MaxPrtAgeHours`. |
| `Remediate-PrimaryRefreshToken.ps1` | Runs `dsregcmd /refreshprt`, waits for the token to appear, and verifies the update time. Optional workstation lock when the refresh does not land. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-PrimaryRefreshToken.ps1` as the detection script and `Remediate-PrimaryRefreshToken.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No**.
4. Keep `$MaxPrtAgeHours` identical in both scripts. Default is 4 hours, the background refresh interval Microsoft documents.
5. Assign to a pilot user group and check the output before widening the scope. A daily schedule is enough.

## Notes

- The PRT state comes only from the `dsregcmd /status` SSO state section. Field labels are fixed English text, so the result does not depend on the OS language.
- The refresh needs line of sight to Microsoft Entra ID. An off-network device reports `Failed` with the `Attempt Status` code from the last PRT attempt.
- `dsregcmd /refreshprt` schedules the refresh. The script polls for up to `$WaitSeconds` because the token is not renewed in the same second.
- `$LockWorkstationToRefresh` is false by default. When enabled, the script locks the session once because lock and unlock is the documented way to force a refresh.
- The script never signs the user out and never restarts the device. A stale token that keeps coming back points to a device registration or network problem, not to this script.
