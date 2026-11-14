# Update Defender Platform

Defender signatures can be current while the antivirus platform remains outdated. These scripts compare the platform with an approved minimum and install an applicable KB4052623 update through Windows Update Agent.

## Files

| File | Purpose |
|---|---|
| `Detect-DefenderPlatform.ps1` | Checks AMProductVersion against the minimum and reports the engine version. |
| `Remediate-DefenderPlatform.ps1` | Downloads and installs one applicable platform update, then verifies the running platform version. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-DefenderPlatform.ps1` and `Remediate-DefenderPlatform.ps1`.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
4. Set the same approved minimum in both scripts. Assign to a pilot device group first.
5. Schedule daily and review blocked or pending results before expanding deployment.

## Notes

- The default minimum is 4.18.26100.4, the October 2026 release. Review it monthly against your approved rollout ring; meeting the minimum does not mean latest.
- Uses the configured update source without changing WSUS, GPO, Intune settings or hidden updates. Missing offers require source approval, connectivity or rollout investigation.
- Windows 10/11 clients with Defender installed are in scope, including passive mode. Platforms below 4.18.2001.10 require that prerequisite first.
- No restart is initiated. Busy installers, required restarts and an unverified minimum return exit 1; verification retries last about two minutes after installation.
- EULA acceptance is off by default; set `$AcceptUpdateEula = $true` only after approval. Engine version is informational; engine and signature updates are separate from KB4052623.
