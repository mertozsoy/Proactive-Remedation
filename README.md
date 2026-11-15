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
| [`Remove-PerUserChromeZoom`](./Remove-PerUserChromeZoom) | Finds Chrome and Zoom installed under AppData in every user profile and removes them with the uninstall command the app registered for that user. |
| [`Uninstall-OemTrialware`](./Uninstall-OemTrialware) | Detect selected OEM trialware and uninstall matching MSI products without restarting Windows. |
| [`Remediate-FirewallState`](./Remediate-FirewallState) | Enable disabled local Windows Firewall profiles and verify the effective state. |
| [`Set-PointAndPrintSecurity`](./Set-PointAndPrintSecurity) | Restore secure Point and Print values and approved print server lists. |
| [`Remove-EnrollingUserAdmin`](./Remove-EnrollingUserAdmin) | Remove unapproved direct Entra user administrators while preserving groups and local accounts. |
| [`Enable-ApplicationIdentity`](./Enable-ApplicationIdentity) | Start a stopped Application Identity service and verify its running state. |
| [`Set-BitLockerBiosSuspendCount`](./Set-BitLockerBiosSuspendCount) | Restore the approved BitLocker suspend reboot count during a bounded BIOS maintenance window. |
| [`Set-BrowserExtensionUnion`](./Set-BrowserExtensionUnion) | Merge approved group extension lists and add missing Edge and Chrome force-install policy entries. |
| [`Enable-WakeSignIn`](./Enable-WakeSignIn) | Require sign-in after sleep for unmanaged AC and battery settings on the active power plan. |
| [`Set-EventLogMaxSize`](./Set-EventLogMaxSize) | Increase undersized Security, AppLocker and PowerShell event log limits without clearing events. |
| [`Disable-BuiltinAccounts`](./Disable-BuiltinAccounts) | Disable enabled Guest and explicitly selected unused built-in accounts by SID. |
| [`Remove-QuickAssist`](./Remove-QuickAssist) | Remove Quick Assist registrations, provisioning and the legacy capability from prohibited devices. |
| [`Update-DefenderPlatform`](./Update-DefenderPlatform) | Update an outdated Defender Antivirus platform through the configured Windows Update source. |
| [`Repair-HostsFile`](./Repair-HostsFile) | Restores the hosts file to an approved baseline and removes stale or malicious entries. |
| [`Enable-UAC`](./Enable-UAC) | Turns User Account Control back on when EnableLUA was disabled locally. |
| [`Repair-PrintSpooler`](./Repair-PrintSpooler) | Start the Print Spooler service and clear print jobs stuck in error state. |
| [`Repair-PrimaryRefreshToken`](./Repair-PrimaryRefreshToken) | Refresh a missing or stale Primary Refresh Token for the signed-in user without a sign-out. |
| [`Disable-RdpAccess`](./Disable-RdpAccess) | Disable Remote Desktop and the port 3389 firewall rules on clients that are not approved for RDP. |
| [`Remove-DefenderLocalExclusions`](./Remove-DefenderLocalExclusions) | Removes Microsoft Defender Antivirus exclusions that were added locally and are not set by policy. |
| [`Set-CachedLogonCount`](./Set-CachedLogonCount) | Lower CachedLogonsCount so former or shared users cannot sign in offline with cached credentials. |
| [`Set-DellBiosSettings`](./Set-DellBiosSettings) | Keep a standard Dell BIOS baseline by reading and writing WMI attributes. |
| [`Remove-TattooedPowerSettings`](./Remove-TattooedPowerSettings) | Removes power policy values left behind after a power profile is unassigned, so users can change lid close and sleep settings again. |
| [`Remove-NonDefaultSmbShares`](./Remove-NonDefaultSmbShares) | Removes SMB shares on workstations that are not built-in administrative shares and not on the allow list. |
| [`Remove-UnapprovedLocalAccounts`](./Remove-UnapprovedLocalAccounts) | Disables or deletes local user accounts that are missing from the approved list. |
| [`Repair-DomainAdminsLocalGroup`](./Repair-DomainAdminsLocalGroup) | Re-add the configured AD group to the local Administrators group when it disappears on a hybrid joined device. |
| [`Set-DevicePrimaryUserAdmin`](./Set-DevicePrimaryUserAdmin) | Grant local admin only to the mapped user of each device when the profile exists. |
| [`Remediate-SmartScreen`](./Remediate-SmartScreen) | Turn Microsoft Defender SmartScreen back on when the device or Edge setting is disabled. |
| [`Set-NtlmV2Level`](./Set-NtlmV2Level) | Raise LmCompatibilityLevel to 5 so clients send NTLMv2 only and refuse LM and NTLM. |

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
| [`Reinstall-CompanyPortal`](./Reinstall-CompanyPortal) | Detects a missing or broken Company Portal app and reinstalls it from a staged bundle or resets the registration so the Intune Store app deploys it again. |
| [`Update-StoreApps`](./Update-StoreApps) | Request a device-context Microsoft Store app update scan without changing policies. |
| [`Remove-ConfigMgrClient`](./Remove-ConfigMgrClient) | Remove an approved ConfigMgr client with its supported uninstaller and report residual paths. |
| [`Remove-TattooedPolicyValues`](./Remove-TattooedPolicyValues) | Remove explicitly approved retired machine policy values after registry backup. |
| [`Set-HybridDeviceName`](./Set-HybridDeviceName) | Rename approved hybrid joined workstations to assigned names without an automatic restart. |
| [`Remove-StuckImeIncoming`](./Remove-StuckImeIncoming) | Remove old unchanged zero-byte IME Incoming download files. |
| [`Enable-StoreServices`](./Enable-StoreServices) | Restore disabled Microsoft Store deployment services to demand start. |
| [`Repair-ConfigMgrClientHealth`](./Repair-ConfigMgrClientHealth) | Repairs a stopped or unresponsive Configuration Manager client on co-managed devices and verifies the assigned site. |
| [`Set-EspUserStatusPage`](./Set-EspUserStatusPage) | Marks the user Enrollment Status Page as skipped on provisioned devices so it does not reappear at every sign-in. |
| [`Remediate-HealthScriptsSchedule`](./Remediate-HealthScriptsSchedule) | Reset stale IME HealthScripts execution state so remediations run on schedule again. |
| [`Repair-MDMEnrollment`](./Repair-MDMEnrollment) | Start the Group Policy auto-enrollment task on a hybrid Entra joined device that has no active Intune enrollment. |
| [`Repair-MDMCertReference`](./Repair-MDMCertReference) | Restore the MDM SslClientCertReference value from the enrollment record or the newest Intune MDM certificate. |
| [`Enable-AppInstaller`](./Enable-AppInstaller) | Remove the disabled App Installer policy value so Intune Store app installs work again. |
| [`Report-IMEVersion`](./Report-IMEVersion) | Reports the Intune Management Extension version and flags devices below the supported 1.58.103.0 minimum. |
| [`Report-MdmEnrollmentGuids`](./Report-MdmEnrollmentGuids) | Report leftover and duplicate MDM enrollment GUIDs on a device together with the ConfigMgr state and recent auto-enrollment failures. |
| [`Remediate-OmadmClient`](./Remediate-OmadmClient) | Terminate omadmclient.exe processes that stayed running past the sync threshold. |

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
| [`Update-DellCommandUpdate`](./Update-DellCommandUpdate) | Apply Dell driver and firmware updates with optional BIOS updates and scan verification. |
| [`Repair-ComponentStore`](./Repair-ComponentStore) | Detect component store corruption and repair repairable Windows images with DISM. |
| [`Repair-WindowsUpdateServiceStart`](./Repair-WindowsUpdateServiceStart) | Restore disabled Windows Update service startup modes without resetting update components. |
| [`Remove-WUDriverExclusion`](./Remove-WUDriverExclusion) | Remove a retired Windows Update driver exclusion after policy review and backup. |
| [`Remediate-Windows10Esu`](./Remediate-Windows10Esu) | Install and activate the Windows 10 ESU MAK key and verify the license state. |
| [`Enable-MicrosoftUpdateService`](./Enable-MicrosoftUpdateService) | Register the Microsoft Update service so Office and driver updates are offered to the device. |

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
| [`Remove-StalePrinterQueues`](./Remove-StalePrinterQueues) | Remove explicitly retired printer queues from the signed-in user's printer inventory. |
| [`Remediate-RequiredPrinters`](./Remediate-RequiredPrinters) | Adds missing approved shared printer connections for the signed-in user. |
| [`Set-UserAppDefaults`](./Set-UserAppDefaults) | Check protocol defaults and verify user-assisted changes through Windows Settings. |
| [`Remove-UnwantedTaskbarPins`](./Remove-UnwantedTaskbarPins) | Remove Microsoft Store and Copilot taskbar pins in the signed-in user's session. |
| [`Repair-StartMenuRegistration`](./Repair-StartMenuRegistration) | Repair per-user Start menu and ShellExperienceHost registrations from existing system manifests. |
| [`Repair-FirstLogonExplorer`](./Repair-FirstLogonExplorer) | Restart the current user's Explorer shell once for an eligible new profile. |
| [`Remove-DefaultUserZero`](./Remove-DefaultUserZero) | Remove the leftover defaultuser0 account and its verified unloaded profile after provisioning. |
| [`Repair-ApprovedPrinterDrivers`](./Repair-ApprovedPrinterDrivers) | Preinstall approved printer drivers as SYSTEM without weakening Point and Print security. |
| [`Repair-WamRegistration`](./Repair-WamRegistration) | Repair missing or unhealthy per-user AAD BrokerPlugin and CloudExperienceHost registrations. |
| [`Set-BatteryProcessorMinimum`](./Set-BatteryProcessorMinimum) | Raise the active power plan's minimum processor state on battery without changing AC settings. |
| [`Set-PowerMode`](./Set-PowerMode) | Reset the AC and DC power mode to Balanced when 24H2 energy recommendations select Best power efficiency. |
| [`Repair-SearchIndex`](./Repair-SearchIndex) | Repairs the Windows Search service and rebuilds the index database when Start menu search returns nothing. |
| [`Set-TeamsCustomBackgrounds`](./Set-TeamsCustomBackgrounds) | Copies corporate Teams background images into the signed-in user's new Teams Uploads folder and restores missing ones. |
| [`Set-DisplayScaling`](./Set-DisplayScaling) | Return the signed-in user to per-monitor display scaling when a forced single scale is leaving a docked external monitor unreadable. |
| [`Repair-EdgeProfileSelection`](./Repair-EdgeProfileSelection) | Repair Edge profile selection and pinned shortcuts that open the wrong profile. |

### Disk cleanup

| Folder | Purpose |
|---|---|
| [`Remove-DellSupportAssistSnapshots`](./Remove-DellSupportAssistSnapshots) | Removes Dell SupportAssist recovery snapshots that fill the disk |
| [`Remediate-FeatureUpdateDiskSpace`](./Remediate-FeatureUpdateDiskSpace) | Free system drive space before a feature update and verify the configured free-space target. |
| [`Remove-OldIMECache`](./Remove-OldIMECache) | Remove old IMECache application content after retention and installer activity checks. |
| [`Remove-AgedRecycleBinItems`](./Remove-AgedRecycleBinItems) | Find and optionally remove Recycle Bin items deleted more than 30 days ago. |
| [`Remove-BrowserCache`](./Remove-BrowserCache) | Remove oversized Edge and Chrome disk cache files from unloaded local profiles. |
| [`Remove-OrphanedUserFolders`](./Remove-OrphanedUserFolders) | Removes folders under the profiles root that have no ProfileList entry and are not loaded. |
| [`Remove-WindowsUpgradeLeftovers`](./Remove-WindowsUpgradeLeftovers) | Remove Windows.old and setup leftovers after the rollback window and clean the component store with DISM. |
| [`Remediate-OneDriveDiskSpace`](./Remediate-OneDriveDiskSpace) | Frees local disk space by converting locally available OneDrive files to online-only when free space is low. |
| [`Remove-WinGetComLogs`](./Remove-WinGetComLogs) | Removes oversized WinGet COM log files from C:\Windows\Temp\WinGet before they fill the system disk. |
| [`Remove-OrphanedInstallerFiles`](./Remove-OrphanedInstallerFiles) | Removes MSI and MSP files in the Windows Installer cache that no registered product or patch references. |

### Office and Teams

| Folder | Purpose |
|---|---|
| [`Set-OutlookComposeFont`](./Set-OutlookComposeFont) | Restore approved classic Outlook compose and reply font defaults for the signed-in user. |
| [`Update-NewTeams`](./Update-NewTeams) | Detect outdated new Teams versions and optionally update with an approved Teams bootstrapper. |
| [`Repair-OfficeC2RUpdates`](./Repair-OfficeC2RUpdates) | Repair a configured local Microsoft 365 Apps update source and refresh update detection. |
| [`Disable-NewOutlookMigration`](./Disable-NewOutlookMigration) | Hide the new Outlook toggle and disable automatic migration for classic Outlook users. |
| [`Remove-NewOutlook`](./Remove-NewOutlook) | Remove unwanted new Outlook installations and provisioning after approval. |
| [`Remove-ExtraOfficeProducts`](./Remove-ExtraOfficeProducts) | Remove explicitly selected preinstalled Office Click-to-Run products while preserving Microsoft 365 Apps. |
| [`Repair-WebView2Runtime`](./Repair-WebView2Runtime) | Install missing machine-wide WebView2 Runtime and retry installation when runtime file checks fail. |
| [`Remove-OfficeUpdateLeftovers`](./Remove-OfficeUpdateLeftovers) | Clear approved retired Office update management overrides. |
| [`Repair-SharedComputerActivation`](./Repair-SharedComputerActivation) | Reset stale or corrupt shared computer activation licensing tokens for the signed-in user. |
| [`Update-M365AppsMinimumBuild`](./Update-M365AppsMinimumBuild) | Detect Microsoft 365 Apps builds below an approved minimum and optionally trigger a Click-to-Run update. |
| [`Set-TeamsForegroundStart`](./Set-TeamsForegroundStart) | Force the new Teams client to start in the foreground for the signed-in user and verify the per-user setting. |
| [`Remediate-OutlookBrowserLinks`](./Remediate-OutlookBrowserLinks) | Points classic Outlook back to the Windows default browser by fixing the per-user link preference that Microsoft 365 Business plans cannot manage with policy. |
| [`Enable-TeamsOutlookNotifications`](./Enable-TeamsOutlookNotifications) | Turns per-user Teams and Outlook desktop notifications back on when Windows notification settings disabled them. |
| [`Set-TeamsAutoStart`](./Set-TeamsAutoStart) | Enable and verify the new Teams startup task for the signed-in user so the client starts at logon. |
| [`Remediate-OutlookOstSize`](./Remediate-OutlookOstSize) | Measures OST files of loaded Outlook profiles and disables shared folder caching when no policy value exists. |
| [`Remediate-TeamsFirewallPrompt`](./Remediate-TeamsFirewallPrompt) | Adds machine wide inbound firewall allow rules for Microsoft Teams and removes leftover Query User block rules on shared PCs. |

### Network and VPN

| Folder | Purpose |
|---|---|
| [`Remove-StaleClientCertificates`](./Remove-StaleClientCertificates) | Remove approved obsolete device client certificates while retaining the replacement and private keys. |
| [`Remove-RetiredServerDrives`](./Remove-RetiredServerDrives) | Remove approved drive mappings to retired file servers. |
| [`Repair-CiscoVpnProfile`](./Repair-CiscoVpnProfile) | Restore a missing Cisco Secure Client VPN profile XML without overwriting existing profiles. |
| [`Repair-ScepWifiConnection`](./Repair-ScepWifiConnection) | Retry a disconnected machine EAP-TLS Wi-Fi connection after its certificate becomes available. |
| [`Repair-FortiClientVpnTunnel`](./Repair-FortiClientVpnTunnel) | Restore missing basic SSL VPN tunnel settings on standalone FortiClient VPN 7.x devices. |
| [`Repair-GlobalProtectSettings`](./Repair-GlobalProtectSettings) | Repair GlobalProtect portal and optional pre-logon bootstrap settings. |
| [`Set-DnsSuffixSearchList`](./Set-DnsSuffixSearchList) | Adds the DNS suffix search list on Microsoft Entra joined devices so short names resolve. |
| [`Remove-TemporaryWifiProfile`](./Remove-TemporaryWifiProfile) | Removes temporary onboarding Wi-Fi profiles left on the device after provisioning. |
| [`Disable-DockNicPowerSaving`](./Disable-DockNicPowerSaving) | Turn off NIC power saving and Energy Efficient Ethernet on dock and USB-C Ethernet adapters. |
| [`Disable-DockPowerSaving`](./Disable-DockPowerSaving) | Turn off PCI Express link state power management and USB selective suspend in the active power scheme so dock Ethernet and USB devices survive sleep. |
| [`Remediate-VpnLeftDns`](./Remediate-VpnLeftDns) | Reset static DNS servers left on physical adapters by a VPN client and verify the DHCP DNS list. |

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
| [`Remove-OrphanUninstallKeys`](./Remove-OrphanUninstallKeys) | Remove orphaned uninstall registry keys left by deleted applications after a registry backup. |
| [`Report-NetworkPstFiles`](./Report-NetworkPstFiles) | Scans network share roots and mapped drives for Outlook PST files and reports their count and size. |

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
