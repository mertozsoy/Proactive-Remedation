<#
.SYNOPSIS
  Remediation script for Teams and Outlook desktop notifications.

.DESCRIPTION
  Turns the per-user toast notification switch back on and clears the disabled state on Teams and Outlook entries. Backs up every registry key with reg export before the change. Leaves policy controlled values alone and reports them. Exits 0 if the settings are on, 1 if not.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$AppPatterns      = @('*MSTeams*', '*OutlookForWindows*', '*OUTLOOK.EXE*')
$RestartPushService = $false
$NotificationRoot = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings'
$PushRoot         = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications'
$PolicyPaths      = @(
    'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'
)

$PackageName = 'TeamsOutlookNotifications'
$Phase       = 'Remediate'
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

function Initialize-BackupDir {
    $path = Join-Path $env:ProgramData 'IntuneRemediations\Backup'
    try {
        if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null }
        return $path
    }
    catch {
        $path = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Backup'
        if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null }
        return $path
    }
}
function Export-RegBackup { param([string]$RegPath, [string]$Label)
    $safeName = $Label -replace '[^A-Za-z0-9._-]', '_'
    $file = Join-Path $script:BackupDir ('{0}_{1}.reg' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $safeName)
    & reg.exe export $RegPath $file /y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "reg export failed for $RegPath" }
    Write-IRTLog "Backup written for $RegPath"
}

try {
    if (Get-PolicyState -ne 'None') { Exit-Script 1 'Blocked | Policy=NoToastApplicationNotification; Action=None' }

    $BackupDir = Initialize-BackupDir
    $changed = 0
    $actions = @()

    if (Get-ToastState -eq 'Off') {
        Export-RegBackup -RegPath 'HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications' -Label 'PushNotifications'
        Set-ItemProperty -LiteralPath $PushRoot -Name ToastEnabled -Value 1 -Type DWord -Force -ErrorAction Stop
        $changed++
        $actions += 'ToastEnabled=On'
        Write-IRTLog 'Enabled toast notifications for the user'
    }

    foreach ($app in @(Get-AppNotificationState | Where-Object { $_.State -eq 'Off' })) {
        $appPath = Join-Path $NotificationRoot $app.Name
        Export-RegBackup -RegPath ('HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\' + $app.Name) -Label ('App_' + $app.Name)
        Set-ItemProperty -LiteralPath $appPath -Name Enabled -Value 1 -Type DWord -Force -ErrorAction Stop
        $changed++
        $actions += "$($app.Name)=On"
        Write-IRTLog "Enabled notifications for $($app.Name)"
    }

    if ($RestartPushService -and $changed -gt 0) {
        try {
            Get-Service -Name 'WpnUserService*' -ErrorAction Stop | Restart-Service -Force -ErrorAction Stop
            Write-IRTLog 'Windows Push Notifications User Service restarted'
        }
        catch { Write-IRTLog "Push service restart skipped: $($_.Exception.Message)" 'WARN' }
    }

    $toast = Get-ToastState
    $apps  = @(Get-AppNotificationState)
    $off   = @($apps | Where-Object { $_.State -eq 'Off' })
    $summary = "ToastEnabled=$toast; Apps=$($apps.Count); Off=$($off.Count); Changed=$changed"
    $backupState = 'None'
    if ($changed -gt 0) { $backupState = 'Saved' }
    if ($toast -eq 'On' -and $off.Count -eq 0) {
        Exit-Script 0 "Fixed | $summary; Actions=$($actions -join ','); Backup=$backupState"
    }
    Exit-Script 1 "Failed | $summary; Actions=$($actions -join ','); Backup=$backupState"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
