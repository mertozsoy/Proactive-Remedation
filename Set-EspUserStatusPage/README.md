# Set ESP User Status Page

A pre-provisioned device can show the Enrollment Status Page again at every restart or when a new user signs in. The user phase of the ESP is not marked as skipped, so Windows runs it again for the new profile. This pair reads the ESP settings of each MDM enrollment and writes the documented skip value for the user status page.

## Files

| File | Purpose |
|---|---|
| `Detect-EspUserStatusPage.ps1` | Reads `SkipUserStatusPage` under `HKLM\SOFTWARE\Microsoft\Enrollments\{GUID}\FirstSync` for MDM enrollments. Flags an enrollment when the device is provisioned and the value is not `0xffffffff`. |
| `Remediate-EspUserStatusPage.ps1` | Exports the `FirstSync` key to `%ProgramData%\IntuneRemediations\Backup` and sets `SkipUserStatusPage` to `0xffffffff`, then reads the value back. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-EspUserStatusPage.ps1` as the detection script and `Remediate-EspUserStatusPage.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- The change is only written when the device is already provisioned: the `HasProvisioningCompleted` value is 1, or the enrollment is older than `$MinProvisionDays`.
- `0xffffffff` is the documented value of the DMClient CSP `FirstSyncStatus/SkipUserStatusPage` node. If an ESP profile in Intune still shows the user page, an MDM refresh can write it back. The lasting fix is the OMA-URI setting in that profile.
- The device status page is not touched. `$SkipDeviceStatusPage` turns that part on, the default is `$false`.
- A `.reg` backup of the `FirstSync` key is written before the first change.
- Medium impact: no reboot and no service restart. The difference shows at the next user sign-in.
