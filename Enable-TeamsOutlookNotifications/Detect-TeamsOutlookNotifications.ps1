<#
.SYNOPSIS
  Detection script for Teams and Outlook desktop notifications.

.DESCRIPTION
  Reads the per-user Windows notification settings. Exits 1 if toast notifications are off for the user, if a Teams or Outlook entry is disabled, or if a policy blocks toast notifications. Exits 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$AppPatterns = @('*MSTeams*', '*OutlookForWindows*', '*OUTLOOK.EXE*')
$NotificationRoot = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings'
$PushRoot         = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications'
$PolicyPaths      = @(
    'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'
)

$PackageName = 'TeamsOutlookNotifications'
$Phase       = 'Detect'
$LogDir      = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile     = Join-Path $LogDir "IRT_$PackageName.log"
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-PolicyState {
    foreach ($path in $PolicyPaths) {
        $value = (Get-ItemProperty -LiteralPath $path -Name NoToastApplicationNotification -ErrorAction SilentlyContinue).NoToastApplicationNotification
        if ($null -ne $value -and [string]$value -eq '1') { return 'NoToastApplicationNotification' }
    }
    return 'None'
}
function Get-ToastState {
    $value = (Get-ItemProperty -LiteralPath $PushRoot -Name ToastEnabled -ErrorAction SilentlyContinue).ToastEnabled
    if ($null -ne $value -and [string]$value -eq '0') { return 'Off' }
    return 'On'
}
function Get-AppNotificationState {
    if (-not (Test-Path -LiteralPath $NotificationRoot)) { return @() }
    $result = @()
    foreach ($key in @(Get-ChildItem -LiteralPath $NotificationRoot -ErrorAction SilentlyContinue)) {
        $match = $false
        foreach ($pattern in $AppPatterns) {
            if ($key.PSChildName -like $pattern) { $match = $true; break }
        }
        if (-not $match) { continue }
        $value = (Get-ItemProperty -LiteralPath $key.PSPath -Name Enabled -ErrorAction SilentlyContinue).Enabled
        $state = 'On'
        if ($null -ne $value -and [string]$value -eq '0') { $state = 'Off' }
        $result += [pscustomobject]@{ Name = $key.PSChildName; State = $state }
    }
    return @($result)
}

try {
    $policy = Get-PolicyState
    $toast  = Get-ToastState
    $apps   = @(Get-AppNotificationState)
    $off    = @($apps | Where-Object { $_.State -eq 'Off' })
    $offNames = (@($off | ForEach-Object { $_.Name }) -join ',')

    $summary = "ToastEnabled=$toast; Apps=$($apps.Count); Off=$($off.Count); Policy=$policy"
    if ($off.Count -gt 0) { $summary = "$summary; OffApps=$offNames" }
    if ($policy -ne 'None') { Exit-Script 1 "Blocked | $summary" }
    if ($toast -eq 'Off' -or $off.Count -gt 0) { Exit-Script 1 "Drift | $summary" }
    if ($apps.Count -eq 0) { Exit-Script 0 "NotApplicable | NoTeamsOrOutlookEntry; ToastEnabled=$toast; Policy=$policy" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
