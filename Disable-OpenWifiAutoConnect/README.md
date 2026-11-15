# Disable Open Wi-Fi Auto Connect

Intune Remediations script pair. A device keeps every Wi-Fi profile a user created, and an open profile with `connectionMode` auto makes the device join that network whenever it is in range. This pair finds unsecured profiles in the machine WLAN store and switches them to manual.

## Files

| File | Purpose |
|---|---|
| `Detect-OpenWifiAutoConnect.ps1` | Reads every profile XML under `%ProgramData%\Microsoft\Wlansvc\Profiles\Interfaces`, keeps the ones with `authentication` open and `encryption` none, and reports those with `connectionMode` auto. `$KeepProfileNames` protects SSIDs that must keep auto-connect. `$DisableHotspotAutoConnect` adds the hotspot policy value to the check. |
| `Remediate-OpenWifiAutoConnect.ps1` | Runs `netsh wlan set profileparameter connectionmode=manual` for each profile, optionally sets `AutoConnectAllowedOEM` to 0 under `HKLM\SOFTWARE\Microsoft\wcmsvc\wifinetworkmanager\config`, then re-reads the store and checks that no open profile is left on auto. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-OpenWifiAutoConnect.ps1` as the detection script and `Remediate-OpenWifiAutoConnect.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Add internal guest or onboarding SSIDs that must connect on their own into `$KeepProfileNames`.
- Passpoint profiles, the ones with a `Hotspot2` element, are skipped.
- A profile delivered by an Intune Wi-Fi configuration profile comes back on the next policy refresh. Change the profile there instead.
- The profile is kept. Only auto-connect is turned off, so the user picks that network manually from then on.
- `$DisableHotspotAutoConnect` is `$false` by default because `AutoConnectAllowedOEM` maps to the WiFiSense policy. Set the policy in Intune or enable the variable.
