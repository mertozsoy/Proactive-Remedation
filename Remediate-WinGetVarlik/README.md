# Remediate WinGet Presence

Intune Proactive Remediation pair that ensures **winget (App Installer)** is present and functional on a device, installing or repairing it if not.

## Files

| File | Purpose |
|---|---|
| `Detect-WinGetVarlik.ps1` | Resolves `winget.exe` from PATH, the per-user WindowsApps folder, or the system WindowsApps package folder, then runs `winget --version` to confirm it actually executes. Exits `0` if present and working, `1` otherwise. Logs to `C:\Temp\IntunePR-WinGetVarlik-Detection.log`. |
| `Remediate-WinGetVarlik.ps1` | If the `Microsoft.DesktopAppInstaller` Appx package exists but doesn't run, attempts an in-place re-registration first. If that fails or the package is missing entirely, downloads the App Installer MSIX bundle from `https://aka.ms/getwinget` and installs it via `Add-AppxPackage -ForceUpdateFromAnyVersion`, then re-verifies. Exits `0` on success, `1` on failure. Logs to `C:\Temp\IntunePR-WinGetKur-Remediation.log`. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context**.
4. Requires outbound internet access to `aka.ms`/the Microsoft Store CDN to download the App Installer bundle, and the VCLibs/UI.Xaml Appx dependencies already present (standard on current Windows 10/11 builds).

## Notes

- No environment-specific values are present in these scripts. `https://aka.ms/getwinget` is Microsoft's official App Installer download redirect, and `9NBLPGH4N681` is the public Microsoft Store product ID for App Installer — neither is sensitive.
- Existing remediations in this repo that rely on `winget` (e.g. `Update-JavaRuntime`, `Update-AcrobatDC`, `Update-TightVNC`) assume winget is already present; deploy this one first if winget coverage isn't guaranteed on your fleet.
