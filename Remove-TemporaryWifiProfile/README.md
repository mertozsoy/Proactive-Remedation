# Remove Temporary Wi-Fi Profile

Intune Remediations script pair. Provisioning often joins a device to a temporary PSK Wi-Fi profile to reach the network. That profile stays on the device after the build, and the device keeps picking it over the corporate SSID. This pair finds the profile by name and removes it with netsh.

## Files

| File | Purpose |
|---|---|
| `Detect-TemporaryWifiProfile.ps1` | Reads the profile XML under `%ProgramData%\Microsoft\Wlansvc\Profiles\Interfaces` and matches profile names against `$TemporaryProfileNames` and `$TemporaryNamePatterns`. `$KeepProfileNames` protects corporate SSIDs. |
| `Remediate-TemporaryWifiProfile.ps1` | Deletes each matching profile with `netsh wlan delete profile`, then re-reads the store and checks that nothing is left. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-TemporaryWifiProfile.ps1` as the detection script and `Remediate-TemporaryWifiProfile.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Add your onboarding profile names to `$TemporaryProfileNames` before deployment. The defaults are examples only.
- Only the machine profile store is read. A profile added with `netsh wlan add profile user=current` lives in the user profile and is not covered.
- Deleting a profile that is currently connected drops the Wi-Fi link until the device reconnects. It is skipped by default.
- A Wi-Fi profile delivered by an Intune configuration profile is re-created by policy. Keep corporate SSIDs in `$KeepProfileNames`.
- `$EnableRemediation = $false` and `$RemoveConnectedProfile = $false` by default. Enable them after you set your own profile names.
