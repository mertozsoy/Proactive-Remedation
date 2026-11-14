<#
.SYNOPSIS
  Remediation script that clears the IME retry state of failed Win32 apps.

.DESCRIPTION
  Removes the failed app state and its matching GRS entry so IME retries the install on its next app check-in. Exits 0 if the state was cleared, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AppIdFilter       = @()
$IgnoredErrorCodes = @(0, 3010, 1641)

$PackageName = 'FailedWin32Apps'
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

function Remove-GrsEntry { param([string]$UserKey, [string]$AppId)
    $removed = 0
    $grsRoot = "$UserKey\GRS"
    if (-not (Test-Path -LiteralPath $grsRoot)) { return 0 }
    foreach ($grsKey in Get-ChildItem -LiteralPath $grsRoot -ErrorAction SilentlyContinue) {
        $names = (Get-ItemProperty -LiteralPath $grsKey.PSPath -ErrorAction SilentlyContinue).PSObject.Properties.Name
        if ($names | Where-Object { $_ -like "$AppId*" }) {
            Remove-Item -LiteralPath $grsKey.PSPath -Recurse -Force -ErrorAction Stop
            Write-IRTLog "GRS entry removed for $AppId ($($grsKey.PSChildName))"
            $removed++
        }
    }
    $removed
}

try {
    if (-not (Test-Path -LiteralPath $Win32AppsRoot)) { Exit-Script 0 'NotApplicable | Win32Apps state not found' }

    $failed = @(Get-FailedWin32App)
    if ($failed.Count -eq 0) { Exit-Script 0 'Healthy | FailedApps=0' }

    $grsRemoved = 0
    foreach ($app in $failed) {
        $grsRemoved += Remove-GrsEntry -UserKey $app.UserKey -AppId $app.AppId
        Remove-Item -LiteralPath $app.AppKey -Recurse -Force -ErrorAction Stop
        Write-IRTLog "App state removed: $($app.AppId) error $($app.ErrorCode)"
    }

    $left = @(Get-FailedWin32App)
    $apps = ($failed | Sort-Object AppId -Unique | ForEach-Object { $_.AppId }) -join ','
    if ($left.Count -gt 0) { Exit-Script 1 "Failed | Remaining=$($left.Count); Apps=$apps" }
    Exit-Script 0 "Reset | Apps=$apps; GrsRemoved=$grsRemoved; Retry=next IME app check-in"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
