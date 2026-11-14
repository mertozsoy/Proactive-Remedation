# Report MDM Enrollment GUIDs

Detection only script for Intune Remediations. A device that was re-enrolled or moved between management tools can keep old enrollment records under the Enrollments key. Those records show up as extra management entries and can block a new auto-enrollment. This script reports what is stored on the device and separates active records from leftovers.

## Files

| File | Purpose |
|---|---|
| `Detect-MdmEnrollmentGuids.ps1` | Reads every enrollment GUID under `HKLM:\SOFTWARE\Microsoft\Enrollments`, with its `ProviderID` and `EnrollmentState`. Counts active Intune records, active records from other providers and leftovers. Adds the `CcmExec` service state, the co-managed view and the number of event 76 entries in the last 14 days. GUIDs go to the log file. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-MdmEnrollmentGuids.ps1` as the detection script. Leave the remediation script empty.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Weekly.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Report only. The script never deletes an enrollment key. Removing the wrong key leaves the device unmanaged, so cleanup stays a manual decision.
- A record is counted as active when `EnrollmentState` is 1. Raw values are written to the log so a different state number can be checked against the device record.
- `CoManaged=Yes` only means that the ConfigMgr client service and an active Intune enrollment are both present on the device.
- `AutoEnrollFail14=Unknown` means the enrollment event log could not be read. Run the script in 64-bit PowerShell with system rights.
- Compare the leftover GUIDs with the enrollment list in Intune and with the Entra device record before you touch anything.
