<#
.SYNOPSIS
  Detection script for failed Win32 app installs waiting on the IME retry timer.

.DESCRIPTION
  Reads the IME Win32 app state and lists apps that report a non-zero install error. Exits 1 if any failed app is found, 0 if none.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AppIdFilter       = @()
$IgnoredErrorCodes = @(0, 3010, 1641)

$PackageName = 'FailedWin32Apps'
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
$GuidPattern   = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
$AppKeyPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}_\d+$'

function Get-FailedWin32App {
    $found = @()
    $userKeys = Get-ChildItem -LiteralPath $Win32AppsRoot -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match $GuidPattern }
    foreach ($userKey in $userKeys) {
        $appKeys = Get-ChildItem -LiteralPath $userKey.PSPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match $AppKeyPattern }
        foreach ($appKey in $appKeys) {
            $appId = $appKey.PSChildName.Split('_')[0]
            if ($AppIdFilter.Count -gt 0 -and $AppIdFilter -notcontains $appId) { continue }
            $raw = (Get-ItemProperty -LiteralPath $appKey.PSPath -Name EnforcementStateMessage -ErrorAction SilentlyContinue).EnforcementStateMessage
            if (-not $raw) { continue }
            try { $state = $raw | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if ($null -eq $state.ErrorCode) { continue }
            $code = [int64]$state.ErrorCode
            if ($IgnoredErrorCodes -contains $code) { continue }
            $found += [pscustomobject]@{ UserKey = $userKey.PSPath; AppKey = $appKey.PSPath; AppId = $appId; ErrorCode = $code }
        }
    }
    $found
}

try {
    if (-not (Test-Path -LiteralPath $Win32AppsRoot)) { Exit-Script 0 'NotApplicable | Win32Apps state not found' }

    $failed = @(Get-FailedWin32App)
    if ($failed.Count -eq 0) { Exit-Script 0 'Healthy | FailedApps=0' }

    $list = ($failed | Sort-Object AppId -Unique | ForEach-Object { '{0}({1})' -f $_.AppId, $_.ErrorCode }) -join ','
    Exit-Script 1 "FailedApps | Count=$(@($failed | Sort-Object AppId -Unique).Count); Apps=$list"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
