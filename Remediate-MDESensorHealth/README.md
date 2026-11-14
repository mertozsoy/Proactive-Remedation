# Remediate MDE Sensor Health

Intune Remediations script pair. Devices show as Inactive or Impaired communications in the Defender portal because the Sense service, or DiagTrack which it depends on, was disabled. This pair brings both back.

## Files

| File | Purpose |
|---|---|
| `Detect-MDESensorHealth.ps1` | Checks `OnboardingState`, and the start type and state of Sense and DiagTrack. |
| `Remediate-MDESensorHealth.ps1` | Sets DiagTrack to Automatic, starts it and starts Sense. It never onboards a device. If onboarding is incomplete it reports it so you can check the EDR onboarding policy. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-MDESensorHealth.ps1` as the detection script and `Remediate-MDESensorHealth.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- If a GPO or privacy setting disables DiagTrack, fix it there as well or the problem will come back.
