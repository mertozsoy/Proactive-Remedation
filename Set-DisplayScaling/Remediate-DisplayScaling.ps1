<#
.SYNOPSIS
  Remediation script for forced single-scale display scaling.

.DESCRIPTION
  Restores per-monitor display scaling for the signed-in user. Backs up the desktop scaling
  registry key, clears the forced single scale values and resets the per-monitor scale cache,
  then verifies the written values. Exits 0 on success, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ExpectedWin8DpiScaling     = 0
$ExpectedDesktopDpiOverride = 0
$RemoveLogPixels            = $true
$ResetPerMonitorCache       = $true
$DesktopKey                 = 'HKCU:\Control Panel\Desktop'
$DesktopKeyHive             = 'HKEY_CURRENT_USER\Control Panel\Desktop'
$PerMonitorKey              = 'HKCU:\Control Panel\Desktop\PerMonitorSettings'
$PerMonitorKeyHive          = 'HKEY_CURRENT_USER\Control Panel\Desktop\PerMonitorSettings'
$BackupFolder               = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Backup'

$PackageName = 'DisplayScaling'
$Phase       = 'Remediate'
$LogDir      = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile     = Join-Path $LogDir "IRT_$PackageName.log"
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Get-DisplayScalingState {
    param([string]$KeyPath, [string]$CachePath)
    $state = [pscustomobject]@{
        Win8DpiScaling     = $null
        DesktopDpiOverride = $null
        LogPixels          = $null
        MonitorCache       = 0
    }
    if (Test-Path -LiteralPath $KeyPath) {
        $props = Get-ItemProperty -LiteralPath $KeyPath -ErrorAction Stop
        $names = @($props.PSObject.Properties.Name)
        if ($names -contains 'Win8DpiScaling') { $state.Win8DpiScaling = [int]$props.Win8DpiScaling }
        if ($names -contains 'DesktopDPIOverride') { $state.DesktopDpiOverride = [int]$props.DesktopDPIOverride }
        if ($names -contains 'LogPixels') { $state.LogPixels = [int]$props.LogPixels }
    }
    if (Test-Path -LiteralPath $CachePath) {
        $state.MonitorCache = @(Get-ChildItem -LiteralPath $CachePath -ErrorAction SilentlyContinue).Count
    }
    return $state
}

function Export-RegistryKey {
    param([string]$HivePath, [string]$FileName)
    if (-not (Test-Path -LiteralPath $BackupFolder)) {
        New-Item -ItemType Directory -Path $BackupFolder -Force -ErrorAction Stop | Out-Null
    }
    $target = Join-Path $BackupFolder $FileName
    & reg.exe export $HivePath $target /y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Registry export returned $LASTEXITCODE for $HivePath" }
    if (-not (Test-Path -LiteralPath $target)) { throw "Registry export file missing for $HivePath" }
    return $target
}

function Format-Value {
    param($Value)
    if ($null -eq $Value) { return 'Unset' }
    return [string]$Value
}

try {
    $ErrorActionPreference = 'Stop'

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
        Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User'
    }

    if (-not (Test-Path -LiteralPath $DesktopKey)) {
        Exit-Script 0 'NotApplicable | DesktopKey=Missing'
    }

    $before = Get-DisplayScalingState -KeyPath $DesktopKey -CachePath $PerMonitorKey
    $fixMode = ($null -ne $before.Win8DpiScaling -and $before.Win8DpiScaling -ne $ExpectedWin8DpiScaling)
    $fixOverride = ($null -ne $before.DesktopDpiOverride -and $before.DesktopDpiOverride -ne $ExpectedDesktopDpiOverride)

    if (-not ($fixMode -or $fixOverride)) {
        Exit-Script 0 ('Healthy | Mode=PerMonitor; Win8DpiScaling={0}; DesktopDPIOverride={1}; LogPixels={2}; Monitors={3}' -f `
            (Format-Value $before.Win8DpiScaling), (Format-Value $before.DesktopDpiOverride), (Format-Value $before.LogPixels), $before.MonitorCache)
    }

    $stamp = Get-Date -Format 'yyyyMMddHHmmss'
    $desktopBackup = Export-RegistryKey -HivePath $DesktopKeyHive -FileName "DisplayScaling_Desktop_$stamp.reg"
    Write-IRTLog "Desktop key exported to $desktopBackup"

    $cacheBackup = 'NotRequested'
    if ($ResetPerMonitorCache -and (Test-Path -LiteralPath $PerMonitorKey)) {
        $cacheBackup = Export-RegistryKey -HivePath $PerMonitorKeyHive -FileName "DisplayScaling_PerMonitorSettings_$stamp.reg"
        Write-IRTLog "Per-monitor cache exported to $cacheBackup"
    }

    New-ItemProperty -LiteralPath $DesktopKey -Name 'Win8DpiScaling' -PropertyType DWord -Value $ExpectedWin8DpiScaling -Force | Out-Null
    New-ItemProperty -LiteralPath $DesktopKey -Name 'DesktopDPIOverride' -PropertyType DWord -Value $ExpectedDesktopDpiOverride -Force | Out-Null

    $logPixelsLabel = Format-Value $before.LogPixels
    if ($RemoveLogPixels -and $null -ne $before.LogPixels) {
        Remove-ItemProperty -LiteralPath $DesktopKey -Name 'LogPixels' -Force -ErrorAction Stop
        $logPixelsLabel = 'Removed'
    }

    $cacheReset = 'No'
    if ($ResetPerMonitorCache -and (Test-Path -LiteralPath $PerMonitorKey)) {
        Remove-Item -LiteralPath $PerMonitorKey -Recurse -Force -ErrorAction Stop
        $cacheReset = 'Yes'
    }

    $after = Get-DisplayScalingState -KeyPath $DesktopKey -CachePath $PerMonitorKey
    $ok = ($after.Win8DpiScaling -eq $ExpectedWin8DpiScaling)
    if ($after.DesktopDpiOverride -ne $ExpectedDesktopDpiOverride) { $ok = $false }
    if ($RemoveLogPixels -and $null -ne $after.LogPixels) { $ok = $false }
    if ($cacheReset -eq 'Yes' -and $after.MonitorCache -ne 0) { $ok = $false }

    if (-not $ok) {
        Exit-Script 1 ('Failed | Mode=PerMonitor; Win8DpiScaling={0}; DesktopDPIOverride={1}; LogPixels={2}; Monitors={3}' -f `
            (Format-Value $after.Win8DpiScaling), (Format-Value $after.DesktopDpiOverride), (Format-Value $after.LogPixels), $after.MonitorCache)
    }

    Exit-Script 0 ('Fixed | Mode=PerMonitor; Win8DpiScaling={0}; DesktopDPIOverride={1}; LogPixels={2}; CacheReset={3}; Effective=NextSignIn' -f `
        $after.Win8DpiScaling, $after.DesktopDpiOverride, $logPixelsLabel, $cacheReset)
}
catch { Exit-Script 1 ('Error: Failed | Operation=Remediate; HResult={0}' -f $_.Exception.HResult) }
