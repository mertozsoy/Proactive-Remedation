<#
.SYNOPSIS
  Detection script for the retired Remote Desktop client on Windows.

.DESCRIPTION
  Finds Remote Desktop Store app registrations, provisioned entries and the MSI
  client named Remote Desktop. Reports whether Windows App is already installed.
  Exits 1 if any legacy client is still present, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$OnlyWhenWindowsAppInstalled = $true
$WindowsAppNamePattern = '*WindowsApp*'
$LegacyNamePattern = '*RemoteDesktop*'
$LegacyPublisherPattern = 'CN=Microsoft*'
$LegacyMsiDisplayName = 'Remote Desktop'

$PackageName = 'LegacyRemoteDesktopClient'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}
function Get-UninstallRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $roots.Add('Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
    $roots.Add('Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($sid in @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue)) {
        if ($sid.PSChildName -notlike 'S-1-5-21-*') { continue }
        if ($sid.PSChildName -like '*_Classes') { continue }
        $roots.Add("Registry::HKEY_USERS\$($sid.PSChildName)\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")
    }
    return $roots
}
function Get-LegacyClientState {
    $apps = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object {
        $_.Name -like $LegacyNamePattern -and
        $_.Name -notlike $WindowsAppNamePattern -and
        $_.Publisher -like $LegacyPublisherPattern
    } | Sort-Object -Property PackageFullName -Unique)
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object {
        $_.DisplayName -like $LegacyNamePattern -and $_.DisplayName -notlike $WindowsAppNamePattern
    })
    $msi = New-Object System.Collections.Generic.List[object]
    foreach ($root in Get-UninstallRoots) {
        foreach ($entry in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            if ([string]$props.DisplayName -ne $LegacyMsiDisplayName) { continue }
            if ([string]$props.Publisher -notlike $LegacyPublisherPattern) { continue }
            $code = $null
            if ([string]$props.UninstallString -match '\{[0-9A-Fa-f\-]{36}\}') { $code = $Matches[0] }
            elseif ($entry.PSChildName -match '^\{[0-9A-Fa-f\-]{36}\}$') { $code = $entry.PSChildName }
            $msi.Add([pscustomobject]@{
                ProductCode = $code
                DisplayVersion = [string]$props.DisplayVersion
                Scope = $entry.PSPath
            })
        }
    }
    $windowsApp = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { $_.Name -like $WindowsAppNamePattern })
    $versions = New-Object System.Collections.Generic.List[string]
    foreach ($app in $apps) { $versions.Add([string]$app.Version) }
    foreach ($item in $msi) { if ($item.DisplayVersion) { $versions.Add($item.DisplayVersion) } }
    $versionText = 'None'
    if ($versions.Count -gt 0) { $versionText = (@($versions | Sort-Object -Unique) -join '/') }
    [pscustomobject]@{
        Apps = $apps
        Provisioned = $provisioned
        Msi = $msi
        Versions = $versionText
        WindowsAppInstalled = ($windowsApp.Count -gt 0)
        Present = ($apps.Count -gt 0 -or $provisioned.Count -gt 0 -or $msi.Count -gt 0)
    }
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [version]$os.Version -lt [version]'10.0') { Exit-Script 0 'NotApplicable | WindowsClient=False' }
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Error | Reason=Use64BitPowerShell' }
    $state = Get-LegacyClientState
    $summary = 'Appx={0}; Provisioned={1}; Msi={2}; WindowsApp={3}; Versions={4}' -f $state.Apps.Count, $state.Provisioned.Count, $state.Msi.Count, $state.WindowsAppInstalled, $state.Versions
    if ($OnlyWhenWindowsAppInstalled -and -not $state.WindowsAppInstalled) { Exit-Script 0 "NotApplicable | $summary" }
    if ($state.Present) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 ('Error | HResult={0}; Reason=InventoryFailed' -f $_.Exception.HResult) }
