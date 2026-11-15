# Repair Wired 802.1X Profile

Intune Remediations script pair for physical Ethernet adapters that lost their 802.1X profile. A Windows feature update can clear the wired profile store, so the Wired AutoConfig service has nothing to authenticate with and the switch port drops the device into the quarantine VLAN. This pair compares every wired adapter with an approved LAN profile XML and puts the profile back.

## Files

| File | Purpose |
|---|---|
| `Detect-Wired8021XProfile.ps1` | Reads `%ProgramData%\Microsoft\dot3svc\Profiles\Interfaces\<InterfaceGUID>` for each physical Ethernet adapter and checks the `dot3svc` service state. `$InterfaceAliasFilter` limits the check to given adapter names. |
| `Remediate-Wired8021XProfile.ps1` | Starts `dot3svc`, adds the approved XML with `netsh lan add profile` on adapters without an 802.1X profile, then reads the profile store again. |

## Deployment (Intune)

1. On a healthy device run `netsh lan export profile folder=C:\Temp` and copy the exported XML to the approved path. Change `$BaselineProfilePath` in both scripts if you use another path.
2. Ship that XML to the device first with a Win32 app or a separate platform script.
3. Go to **Devices > Scripts and remediations > Remediations > Create**.
4. Upload `Detect-Wired8021XProfile.ps1` as the detection script and `Remediate-Wired8021XProfile.ps1` as the remediation script.
5. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Schedule: Daily, pilot group first.

## Notes

- Without the baseline XML the pair reports `NotApplicable` and changes nothing.
- When the wired machine policy key `WiredL2\GP_Policy` exists the remediation reports `Blocked` and leaves the profile to Group Policy.
- Only physical 802.3 adapters are touched. Wireless and virtual adapters are ignored.
- `$ReconnectInterface` is off by default. Turn it on only when the switch port needs a fresh EAPOL start.
- The script never restarts the device and never removes a profile.
