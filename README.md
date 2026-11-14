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
| [`Disable-LLMNR-NetBIOS`](./Disable-LLMNR-NetBIOS) | Keeps LLMNR and NetBIOS over TCP/IP turned off on every adapter |
| [`Remove-PowerShellV2`](./Remove-PowerShellV2) | Removes the Windows PowerShell 2.0 engine |
| [`Remove-WSUSPolicyLeftovers`](./Remove-WSUSPolicyLeftovers) | Removes old WSUS values that block Windows Update for Business |
| [`Remove-StaleUserProfiles`](./Remove-StaleUserProfiles) | Finds and removes local profiles not used for 90 days (report mode by default) |
| [`Detect-RemoteAccessTools`](./Detect-RemoteAccessTools) | Finds installed or portable remote access tools (detection only) |
| [`Remediate-BitLockerProtection`](./Remediate-BitLockerProtection) | Backs up missing recovery keys to Entra ID and handles BitLocker left suspended |
| [`Remediate-SecureBootCA2023`](./Remediate-SecureBootCA2023) | Checks and starts the move to the 2023 Secure Boot certificates |
| [`Remediate-NtlmV1SsoReadiness`](./Remediate-NtlmV1SsoReadiness) | Reports NTLMv1 SSO use and manages time limited audit exceptions |
| [`Remediate-WindowsLAPS`](./Remediate-WindowsLAPS) | Makes sure the LAPS password is backed up to Entra ID or AD |
| [`Update-DefenderSecurityIntelligence`](./Update-DefenderSecurityIntelligence) | Updates old Defender signatures with source fallback |
| [`Remediate-MDESensorHealth`](./Remediate-MDESensorHealth) | Brings back the Sense and DiagTrack services the MDE sensor needs |
| [`Remediate-TimeSync`](./Remediate-TimeSync) | Repairs Windows time synchronization |
| [`Remediate-WinRE`](./Remediate-WinRE) | Turns Windows Recovery Environment back on |
| [`Remediate-WindowsActivation`](./Remediate-WindowsActivation) | Retries Windows activation without changing the product key |
| [`Repair-LapsAccount`](./Repair-LapsAccount) | Creates or enables the local admin account that Windows LAPS manages |
| [`Disable-LegacyTls`](./Disable-LegacyTls) | Turns off TLS 1.0 and 1.1 for SCHANNEL and .NET |
| [`Disable-HelloPostLogonPrompt`](./Disable-HelloPostLogonPrompt) | Stops the forced Windows Hello PIN setup screen after sign-in |
| [`Remove-BrowserExtension`](./Remove-BrowserExtension) | Removes one known bad browser extension from every profile |
| [`Remove-StaleAvRegistration`](./Remove-StaleAvRegistration) | Removes stale third-party antivirus registrations from Windows Security Center so Defender can leave passive mode. |

### Intune agent and device health

| Folder | Purpose |
|---|---|
| [`Remediate-IMEHealth`](./Remediate-IMEHealth) | Restarts an Intune Management Extension that stopped processing |
| [`Remediate-MDMSyncHealth`](./Remediate-MDMSyncHealth) | Repairs the MDM sync prerequisites and starts a sync |
| [`Remediate-HybridJoinState`](./Remediate-HybridJoinState) | Finds hybrid devices that never finished Entra join |
| [`Remediate-ServicingPipelineHealth`](./Remediate-ServicingPipelineHealth) | Fixes devices that show as Unknown in WUfB, Autopatch and Secure Boot reports |
| [`Remediate-TeamsMeetingAddin`](./Remediate-TeamsMeetingAddin) | Repairs the Teams Meeting add-in in classic Outlook (user context) |
| [`Repair-FailedWin32Apps`](./Repair-FailedWin32Apps) | Clears the IME retry state so failed Win32 apps install again |
| [`Repair-RequiredApps`](./Repair-RequiredApps) | Brings back a required app that the user uninstalled |
| [`Enable-MDMSyncTasks`](./Enable-MDMSyncTasks) | Turns disabled Task Scheduler and MDM sync tasks back on |
| [`Remove-LegacyCompanyPortal`](./Remove-LegacyCompanyPortal) | Removes the per-user Company Portal that blocks the system install |
| [`Repair-WebView2Arm64`](./Repair-WebView2Arm64) | Detects an x64 WebView2 Runtime on ARM64 devices and reinstalls the ARM64 runtime. |

### OneDrive

| Folder | Purpose |
|---|---|
| [`Remediate-OneDriveHealth`](./Remediate-OneDriveHealth) | Detects a broken/signed-out OneDrive sync and attempts a full self-heal |
| [`Remediate-OneDriveStartup`](./Remediate-OneDriveStartup) | Ensures OneDrive is registered to launch automatically at sign-in |
| [`Repair-OneDriveKfm`](./Repair-OneDriveKfm) | Starts Known Folder Move again when Desktop and Documents are not redirected |

### Windows Update

| Folder | Purpose |
|---|---|
| [`Remove-TargetReleaseVersionPin`](./Remove-TargetReleaseVersionPin) | Removes a leftover TargetReleaseVersion pin that blocks feature updates |
| [`Remove-WUInternetLocationBlock`](./Remove-WUInternetLocationBlock) | Removes the WSUS value that blocks Store and Company Portal installs |
| [`Remediate-DeliveryOptimizationCache`](./Remediate-DeliveryOptimizationCache) | Cleans an oversized Delivery Optimization cache |
| [`Set-UpdateHealthTools`](./Set-UpdateHealthTools) | Brings Microsoft Update Health Tools to the expected state: installed before 24H2 and removed on 24H2 and later. |

### User experience

| Folder | Purpose |
|---|---|
| [`Enable-AutoTimeZone`](./Enable-AutoTimeZone) | Turns on automatic time zone and the location access it needs |
| [`Add-CompanyShortcuts`](./Add-CompanyShortcuts) | Adds the standard company shortcuts when they are missing (user context) |
| [`Remove-PublicDesktopShortcuts`](./Remove-PublicDesktopShortcuts) | Removes unwanted shortcuts from the Public Desktop |
| [`Remove-SpotlightDesktopIcon`](./Remove-SpotlightDesktopIcon) | Removes the Windows Spotlight Learn about this picture icon |
| [`Repair-InboxApps`](./Repair-InboxApps) | Restores missing Notepad, Snipping Tool, Calculator and Store (user context) |
| [`Repair-NetworkDrives`](./Repair-NetworkDrives) | Maps missing network drives again in the user session |
| [`Set-AcPowerTimeouts`](./Set-AcPowerTimeouts) | Sets sleep and display timeouts on docked and meeting room devices |

### Disk cleanup

| Folder | Purpose |
|---|---|
| [`Remove-DellSupportAssistSnapshots`](./Remove-DellSupportAssistSnapshots) | Removes Dell SupportAssist recovery snapshots that fill the disk |

### Inventory & reporting (detection-only)

| Folder | Purpose |
|---|---|
| [`Inventory-DefaultBrowser`](./Inventory-DefaultBrowser) | Reports the logged-on user's default browser via Intune reporting |
| [`Report-DeviceUptime`](./Report-DeviceUptime) | Reports device uptime since last reboot via Intune reporting |
| [`Report-PendingReboot`](./Report-PendingReboot) | Shows devices waiting for a restart and the reason |
| [`Report-FeatureUpdateReadiness`](./Report-FeatureUpdateReadiness) | Shows safeguard holds, blockers and end of servicing; refreshes old appraiser data |
| [`Report-CertificateExpiry`](./Report-CertificateExpiry) | Lists machine certificates and the Intune MDM certificate close to expiry |
| [`Report-DiskHealth`](./Report-DiskHealth) | Reports failing or worn physical disks |
| [`Report-HardwareInventory`](./Report-HardwareInventory) | Collects BIOS, TPM, battery and other hardware details as one JSON line |
| [`Report-BrowserExtensions`](./Report-BrowserExtensions) | Lists Edge and Chrome extensions that are not on the approved list |
| [`Report-MdmDeviceCertificates`](./Report-MdmDeviceCertificates) | Reports duplicate and expired Intune MDM device certificates |

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
