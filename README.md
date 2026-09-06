# Intune Proactive Remediation Scripts

A collection of [Microsoft Intune Proactive Remediation](https://learn.microsoft.com/en-us/mem/intune/fundamentals/remediations) (Remediation scripts) packages: application removal, application updates, OneDrive health, Windows Update repair, security hardening, and device inventory/reporting.

Each folder is a self-contained, ready-to-upload Proactive Remediation package with a **Detect** script, a **Remediate** script (where applicable), and its own `README.md` explaining exactly what it does, how to deploy it, and what — if anything — needs to be customized before use.

## What is a Proactive Remediation?

Intune Proactive Remediations run on a schedule (or on-demand) on enrolled devices:

1. The **detection** script runs first. Exit code `0` = compliant (nothing to do). Exit code `1` = non-compliant (remediation needed).
2. If detection reports non-compliant, the **remediation** script runs to fix the issue.
3. Both scripts' output and exit codes are reported back to Intune for fleet-wide visibility.

All scripts in this repo are plain PowerShell (`.ps1`), designed to run in the **SYSTEM context** unless a folder's own README says otherwise.

## Repository structure & naming convention

```
<Action>-<Target>/
├── Detect-<Target>.ps1        # detection script (or Detect-*.ps1)
├── Remediate-<Target>.ps1     # remediation script (or Remediate-*.ps1), when applicable
└── README.md                  # what it does, deployment steps, notes/warnings
```

Folder names are prefixed by what the package **does**, so related packages sort together:

| Prefix | Meaning |
|---|---|
| `Uninstall-` | Detects and silently removes an application |
| `Update-` | Detects an outdated app version and updates it (usually via `winget`) |
| `Reinstall-` | "Always remediate" pattern that forces Intune to redeploy a Win32 app |
| `Remediate-` | Detects and fixes a specific misconfiguration or unhealthy state |
| `Remove-` | Detects and removes a specific registry key / leftover artifact |
| `Disable-` | Detects and disables a specific Windows feature/setting |
| `Detect-` | Detection-only package (reporting or manual-remediation use case) |
| `Inventory-` / `Report-` | Detection-only, used purely to surface data in Intune reporting |

## Scripts

### Application removal (`Uninstall-*`)

| Folder | Removes |
|---|---|
| [`Uninstall-Disney`](./Uninstall-Disney) | Disney+ (Microsoft Store app) |
| [`Uninstall-Firefox`](./Uninstall-Firefox) | Mozilla Firefox |
| [`Uninstall-GoogleEarthPro`](./Uninstall-GoogleEarthPro) | Google Earth Pro |
| [`Uninstall-InstagramBeta`](./Uninstall-InstagramBeta) | Instagram Beta (Microsoft Store app) |
| [`Uninstall-ManageEngineMibBrowser5`](./Uninstall-ManageEngineMibBrowser5) | ManageEngine MIB Browser 5 |
| [`Uninstall-MicrosoftTeamsPersonal`](./Uninstall-MicrosoftTeamsPersonal) | Consumer/personal Microsoft Teams (Microsoft Store app) |
| [`Uninstall-Netflix`](./Uninstall-Netflix) | Netflix (Microsoft Store app) |
| [`Uninstall-PuTTY`](./Uninstall-PuTTY) | PuTTY release 0.83 (64-bit) |
| [`Uninstall-Spotify`](./Uninstall-Spotify) | Spotify (Microsoft Store app) |
| [`Uninstall-TikTok`](./Uninstall-TikTok) | TikTok (Microsoft Store app) |
| [`Uninstall-TouchVPN`](./Uninstall-TouchVPN) | TouchVPN (Microsoft Store app) |

### Application & component updates (`Update-*`, `Reinstall-*`)

| Folder | Purpose |
|---|---|
| [`Update-AcrobatDC`](./Update-AcrobatDC) | Keeps Adobe Acrobat Reader DC current via `winget` |
| [`Update-JavaRuntime`](./Update-JavaRuntime) | Keeps Oracle Java 8 Runtime current via `winget` |
| [`Update-TightVNC`](./Update-TightVNC) | Keeps TightVNC current via `winget` |
| [`Reinstall-PCManager`](./Reinstall-PCManager) | Forces reinstall of Microsoft PC Manager |
| [`Reinstall-RemoteHelp`](./Reinstall-RemoteHelp) | Forces reinstall of Remote Help |
| [`Reinstall-WinGet`](./Reinstall-WinGet) | Forces reinstall of WinGet (App Installer) |
| [`Remediate-WinGetVarlik`](./Remediate-WinGetVarlik) | Ensures `winget` itself is present and working; installs/repairs it if not |

### System & security

| Folder | Purpose |
|---|---|
| [`Disable-CredentialGuard`](./Disable-CredentialGuard) | Disables Windows Credential Guard (remediation only) |
| [`Disable-FastBoot`](./Disable-FastBoot) | Detects and disables Windows Fast Startup |
| [`Detect-LocalAdmin`](./Detect-LocalAdmin) | Flags local `Administrators` accounts not on an allow-list (detection only) |
| [`Detect-LowDiskSpace`](./Detect-LowDiskSpace) | Detects low free space on the `C:` drive *(legacy entry — detection script only, no remediation script or README yet)* |
| [`Detect-EFIPartition`](./Detect-EFIPartition) | Detects low free space on the EFI System Partition and can clean up HP firmware update leftovers |
| [`Remove-ClassicTeamsUninstallKey`](./Remove-ClassicTeamsUninstallKey) | Removes the stale uninstall registry key left behind by classic Microsoft Teams, across all user profiles |
| [`Remediate-WindowsUpdate`](./Remediate-WindowsUpdate) | Full Windows Update component reset (services, caches, DLL registration, Winsock) plus SetupDiag diagnostics |

### OneDrive

| Folder | Purpose |
|---|---|
| [`Remediate-OneDriveHealth`](./Remediate-OneDriveHealth) | Detects a broken/signed-out OneDrive sync and attempts a full self-heal |
| [`Remediate-OneDriveStartup`](./Remediate-OneDriveStartup) | Ensures OneDrive is registered to launch automatically at sign-in |

### Inventory & reporting (detection-only)

| Folder | Purpose |
|---|---|
| [`Inventory-DefaultBrowser`](./Inventory-DefaultBrowser) | Reports the logged-on user's default browser via Intune reporting |
| [`Report-DeviceUptime`](./Report-DeviceUptime) | Reports device uptime since last reboot via Intune reporting |

### Utilities (not a Detect/Remediate pair)

| Folder | Purpose |
|---|---|
| [`Add-StartupShortcut-AllUsers`](./Add-StartupShortcut-AllUsers) | Generic template that creates an all-users Startup shortcut for a given application |

## Deployment (general steps)

1. Open **Intune admin center** → **Devices** → **Scripts and remediations** → **Remediations**.
2. Click **Create**, give it a name, and upload the folder's `Detect-*.ps1` as the detection script and `Remediate-*.ps1` (if present) as the remediation script.
3. Set **Run this script using the logged-on credentials** and **Run script in 64-bit PowerShell** per that folder's `README.md` (defaults to system context / 64-bit unless stated otherwise).
4. Assign to a device group and set a run schedule (or run on-demand for testing).
5. **Always pilot on a small test group first**, especially for scripts that uninstall software, reset services, or modify the registry.

## About demo/placeholder values

Where a script originally referenced real internal identifiers (hostnames, usernames, tenant-specific paths, etc.), those values have been replaced with clearly-named placeholders (e.g. `demo.admin`, `UygulamaExeAdi.exe`) before publishing here. **Review and fill in placeholders for your own environment before deploying.** Public, non-sensitive identifiers (Microsoft Store package family names, `winget` package IDs, Intune app IDs, MSI product codes, official Microsoft download URLs) are left as-is since they aren't environment-specific secrets.

## Disclaimer

These scripts are provided as-is. Test in a non-production environment or a small pilot group before wide deployment. Several scripts (Windows Update reset, EFI partition cleanup, Credential Guard) make system-level changes — review each folder's README for warnings before use.
