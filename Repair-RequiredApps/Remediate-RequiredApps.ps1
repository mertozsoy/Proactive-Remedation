<#
.SYNOPSIS
  Remediation script for required Win32 apps that were uninstalled by the user.

.DESCRIPTION
  Removes the cached Intune Management Extension state of the missing apps so the Required assignment is evaluated again. Exits 0 when the cached state is gone, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RequiredApps = @()

$PackageName = 'RequiredApps'
$Phase       = 'Remediate'
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

function Remove-GrsEntry { param([string]$AppId)
    $removed = 0
    foreach ($userKey in Get-ChildItem -LiteralPath $Win32AppsRoot -ErrorAction SilentlyContinue) {
        $grsRoot = Join-Path $userKey.PSPath 'GRS'
        if (-not (Test-Path -LiteralPath $grsRoot)) { continue }
        foreach ($grsKey in Get-ChildItem -LiteralPath $grsRoot -ErrorAction SilentlyContinue) {
            $valueNames = @((Get-Item -LiteralPath $grsKey.PSPath).GetValueNames())
            $subKeys    = @((Get-Item -LiteralPath $grsKey.PSPath).GetSubKeyNames())
            if (($valueNames + $subKeys) | Where-Object { $_ -like "$AppId*" }) {
                Remove-Item -LiteralPath $grsKey.PSPath -Recurse -Force -ErrorAction Stop
                Write-IRTLog "GRS entry removed for $AppId ($($grsKey.PSChildName))"
                $removed++
            }
        }
    }
    $removed
}

try {
    if ($RequiredApps.Count -eq 0) { Exit-Script 0 'NotApplicable | RequiredApps=0' }

    $reset = New-Object System.Collections.Generic.List[string]
    $grsRemoved = 0
    foreach ($app in $RequiredApps) {
        if (Test-AppPresent -App $app) { continue }
        $keys = @(Get-AppStateKey -AppId $app.AppId)
        if ($keys.Count -eq 0) { continue }
        foreach ($key in $keys) {
            Remove-Item -LiteralPath $key.PSPath -Recurse -Force -ErrorAction Stop
            Write-IRTLog "App state removed: $($app.Name) $($key.PSChildName)"
        }
        $grsRemoved += Remove-GrsEntry -AppId $app.AppId
        $reset.Add($app.Name)
    }

    $left = New-Object System.Collections.Generic.List[string]
    foreach ($app in $RequiredApps) {
        if (-not (Test-AppPresent -App $app) -and @(Get-AppStateKey -AppId $app.AppId).Count -gt 0) { $left.Add($app.Name) }
    }

    $summary = 'Apps={0}; GrsRemoved={1}; Retry=next IME app check-in' -f ($reset -join ','), $grsRemoved
    if ($left.Count -gt 0) { Exit-Script 1 "Failed (StateLeft=$($left -join ',')) | $summary" }
    if ($reset.Count -eq 0) { Exit-Script 0 'NoAction | Apps=None' }
    Exit-Script 0 "Reset | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
