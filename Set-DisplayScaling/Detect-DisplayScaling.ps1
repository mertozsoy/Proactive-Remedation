<#
.SYNOPSIS
  Detection script for forced single-scale display scaling.

.DESCRIPTION
  Reads the signed-in user display scaling values from HKCU\Control Panel\Desktop.
  Exits 1 when Windows is forced to one scale for every display, 0 when per-monitor scaling is active.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ExpectedWin8DpiScaling     = 0
$ExpectedDesktopDpiOverride = 0
$DesktopKey                 = 'HKCU:\Control Panel\Desktop'
$PerMonitorKey              = 'HKCU:\Control Panel\Desktop\PerMonitorSettings'

$PackageName = 'DisplayScaling'
$Phase       = 'Detect'
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

    $state = Get-DisplayScalingState -KeyPath $DesktopKey -CachePath $PerMonitorKey
    $modeLabel = 'PerMonitor'
    $issues = @()

    if ($null -ne $state.Win8DpiScaling -and $state.Win8DpiScaling -ne $ExpectedWin8DpiScaling) {
        $modeLabel = 'SingleScale'
        $issues += ('Win8DpiScaling=' + $state.Win8DpiScaling)
    }
    if ($null -ne $state.DesktopDpiOverride -and $state.DesktopDpiOverride -ne $ExpectedDesktopDpiOverride) {
        $issues += ('DesktopDPIOverride=' + $state.DesktopDpiOverride)
    }

    $detail = 'Win8DpiScaling={0}; DesktopDPIOverride={1}; LogPixels={2}; Monitors={3}' -f `
        (Format-Value $state.Win8DpiScaling), (Format-Value $state.DesktopDpiOverride), (Format-Value $state.LogPixels), $state.MonitorCache

    if ($issues.Count -gt 0) {
        Exit-Script 1 "Drift | Mode=$modeLabel; $detail; Expected=PerMonitor"
    }

    Exit-Script 0 "Healthy | Mode=PerMonitor; $detail"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
