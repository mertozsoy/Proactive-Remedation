<#
.SYNOPSIS
  Remediation script for the new Teams open-in-background start setting.

.DESCRIPTION
  Backs up the current user new Teams settings file and sets open_app_in_background to the expected value. Defers while Teams is running and verifies the written value. Exits 0 on success, 1 on failure or deferral.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ExpectedBackgroundStart = $false
$TeamsFamilyName         = 'MSTeams_8wekyb3d8bbwe'
$SettingName             = 'open_app_in_background'
$TeamsProcessName        = 'ms-teams'
$BackupFolder            = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Backup'
$ExpectedLabel           = 'Foreground'
$ExpectedLiteral         = 'false'
if ($ExpectedBackgroundStart) {
    $ExpectedLabel   = 'Background'
    $ExpectedLiteral = 'true'
}

$PackageName = 'TeamsForegroundStart'
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

function Get-TeamsSettingsPath {
    Join-Path $env:LOCALAPPDATA "Packages\$TeamsFamilyName\LocalCache\Microsoft\MSTeams\app_settings.json"
}

function Get-BackgroundStartState {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 'NoFile' }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ($null -eq $raw) { return 'NoFile' }
    if ($raw -match ('"' + $SettingName + '"\s*:\s*(true|false)')) {
        if ($Matches[1] -eq 'true') { return 'Background' }
        return 'Foreground'
    }
    return 'Unset'
}

function Get-UpdatedSettingsContent {
    param([string]$Raw, [string]$Literal)
    $pattern = '"' + $SettingName + '"\s*:\s*(true|false)'
    if ($Raw -match $pattern) {
        return [regex]::Replace($Raw, $pattern, '"' + $SettingName + '":' + $Literal)
    }
    $brace = $Raw.IndexOf('{')
    if ($brace -lt 0) { throw 'Settings file is not a JSON object' }
    return $Raw.Substring(0, $brace + 1) + '"' + $SettingName + '":' + $Literal + ',' + $Raw.Substring($brace + 1)
}

try {
    $ErrorActionPreference = 'Stop'

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
        Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User'
    }

    $settingsPath = Get-TeamsSettingsPath
    $state = Get-BackgroundStartState -Path $settingsPath

    if ($state -eq 'NoFile') { Exit-Script 0 'NotApplicable | SettingsFile=NotCreated' }
    if ($state -eq $ExpectedLabel) { Exit-Script 0 "Healthy | Setting=open_app_in_background; Current=$state" }

    $sessionId = (Get-Process -Id $PID).SessionId
    $teams = @(Get-Process -Name $TeamsProcessName -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sessionId })
    if ($teams.Count -gt 0) {
        Exit-Script 1 'Deferred | Reason=TeamsRunning; Retry=NextSchedule'
    }

    if (-not (Test-Path -LiteralPath $BackupFolder)) { New-Item -ItemType Directory -Path $BackupFolder -Force | Out-Null }
    $backupFile = Join-Path $BackupFolder ('Teams_app_settings_{0}.json' -f (Get-Date -Format 'yyyyMMddHHmmss'))
    Copy-Item -LiteralPath $settingsPath -Destination $backupFile -Force -ErrorAction Stop
    Write-IRTLog "Backup written to $backupFile"

    $raw = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop
    $content = Get-UpdatedSettingsContent -Raw $raw -Literal $ExpectedLiteral
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($settingsPath, $content, $encoding)

    $after = Get-BackgroundStartState -Path $settingsPath
    if ($after -ne $ExpectedLabel) {
        Exit-Script 1 "Failed | Setting=open_app_in_background; Current=$after; Expected=$ExpectedLabel"
    }

    Exit-Script 0 "Fixed | Setting=open_app_in_background; Value=$ExpectedLabel; Backup=Yes; Effective=NextTeamsStart"
}
catch { Exit-Script 1 ('Error: Failed | Operation=Remediate; HResult={0}' -f $_.Exception.HResult) }
