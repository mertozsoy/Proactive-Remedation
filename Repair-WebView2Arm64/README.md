# Repair WebView2 Arm64

Intune Remediations script pair. On Windows on ARM devices Microsoft Edge Update can deliver an x64 build of the WebView2 Runtime. Native ARM64 apps such as the new Teams and the new Outlook then fail to load the runtime. This pair checks the architecture of the installed runtime binary and reinstalls the ARM64 runtime when an installer is staged on the device.

## Files

| File | Purpose |
|---|---|
| `Detect-WebView2Arm64.ps1` | On ARM64 devices reads `pv` from the per-machine WebView2 Edge Update client key in both registry views and checks the PE machine type of `msedgewebview2.exe` under `C:\Program Files (x86)\Microsoft\EdgeWebView\Application\<version>`. Exits 1 when the binary is not ARM64 or is missing. Non ARM64 devices and devices without a per-machine runtime return NotApplicable. |
| `Remediate-WebView2Arm64.ps1` | Runs `$InstallerPath` with `/silent /install`, waits up to `$InstallTimeoutSec`, then checks the PE machine type again. With an empty `$InstallerPath` it only reports. Exits 0 if the binary is ARM64 afterwards. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-WebView2Arm64.ps1` as the detection script and `Remediate-WebView2Arm64.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily or weekly.
5. Assign to a pilot group of ARM64 devices first, check the output, then widen the scope.

## Notes

- The script installs a system runtime. Start with a pilot group.
- Set `$InstallerPath` to `MicrosoftEdgeWebView2RuntimeInstallerARM64.exe` on the device or on a share that the computer account can read. With an empty value the script only reports. The ARM64 standalone installer is about 200 MB, so pre-stage it instead of downloading it on every run.
- Use an ARM64 installer that is newer than the installed x64 build. Edge Update can skip the install when the version is equal. The script checks the binary after the run, so a skipped install is reported as Failed.
- Edge Update can put the x64 build back after a later update. Keep the remediation scheduled and watch the output. The script does not uninstall the runtime and does not restart apps.
- If WebView2 installs are blocked by an Edge Update policy, the installer may fail. The installer exit code is in the log.
- The check covers the per-machine runtime only. A per-user WebView2 install under a user profile is not inspected.
- The per-machine runtime is shared. No user files are touched and no registry keys are deleted.
- Localized Windows is supported because the script reads registry values, CIM and PE headers, not command output.
