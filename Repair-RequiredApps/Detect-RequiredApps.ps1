<#
.SYNOPSIS
  Detection script for required Win32 apps that were uninstalled by the user.

.DESCRIPTION
  Checks the apps listed in $RequiredApps on the device. Exits 1 if an app is missing while the Intune Management Extension still holds a cached state for it, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RequiredApps = @()

$PackageName = 'RequiredApps'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

$Win32AppsRoot = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps'
$UninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

function Test-AppPresent { param($App)
    if ($App.DetectPath) { return (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables($App.DetectPath))) }
    if ($App.DisplayName) {
        foreach ($root in $UninstallRoots) {
            $hit = Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | Where-Object {
                (Get-ItemProperty -LiteralPath $_.PSPath -Name DisplayName -ErrorAction SilentlyContinue).DisplayName -like $App.DisplayName
            } | Select-Object -First 1
            if ($hit) { return $true }
        }
        return $false
    }
    return $true
}

function Get-AppStateKey { param([string]$AppId)
    foreach ($userKey in Get-ChildItem -LiteralPath $Win32AppsRoot -ErrorAction SilentlyContinue) {
        Get-ChildItem -LiteralPath $userKey.PSPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "$AppId*" }
    }
}

try {
    if ($RequiredApps.Count -eq 0) { Exit-Script 0 'NotApplicable | RequiredApps=0' }
    if (-not (Test-Path -LiteralPath $Win32AppsRoot)) { Exit-Script 0 'NotApplicable | Win32Apps state not found' }

    $stale = New-Object System.Collections.Generic.List[string]
    $waiting = New-Object System.Collections.Generic.List[string]
    $present = 0
    foreach ($app in $RequiredApps) {
        if (Test-AppPresent -App $app) { $present++; continue }
        if (@(Get-AppStateKey -AppId $app.AppId).Count -gt 0) { $stale.Add($app.Name) } else { $waiting.Add($app.Name) }
    }

    $summary = 'Configured={0}; Present={1}; MissingWithState={2}; WaitingForInstall={3}' -f $RequiredApps.Count, $present, $stale.Count, $waiting.Count
    if ($stale.Count -gt 0) { Exit-Script 1 "Missing ($($stale -join ',')) | $summary" }
    if ($waiting.Count -gt 0) { Exit-Script 0 "Waiting ($($waiting -join ',')) | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
