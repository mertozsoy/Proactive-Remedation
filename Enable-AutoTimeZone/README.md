# Enable Automatic Time Zone

Intune Remediations script pair. Standard users cannot turn on "Set time zone automatically", so travelling users keep the wrong time zone and their calendar shifts. This pair turns the setting on and makes sure location is available to the system.

## Files

| File | Purpose |
|---|---|
| `Detect-AutoTimeZone.ps1` | Checks `tzautoupdate\Start` (3 = on), the device level location consent (`ConsentStore\location\Value` = `Allow`) and the Geolocation service (`lfsvc`). Also reports a GPO or MDM policy that turns location off. |
| `Remediate-AutoTimeZone.ps1` | Sets `tzautoupdate\Start` to 3, sets the location consent to `Allow`, moves `lfsvc` from Disabled back to Manual and starts it. Verifies the three values. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-AutoTimeZone.ps1` as the detection script and `Remediate-AutoTimeZone.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- If location is turned off by policy (`DisableLocation` GPO or `System/AllowLocation` = 0), the remediation changes nothing and exits 1 with `Blocked`. Fix the policy first.
- The time zone itself is set by Windows after the location service gets a fix. It can take a few minutes.
- Devices behind an always-on VPN or a central proxy can get the time zone of the egress location. Test with a pilot group that includes those users.
- The script only changes the device level consent. Per user app permissions are not touched.
