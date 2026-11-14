<#
.SYNOPSIS
  Detection script for the new Teams open-in-background start setting.

.DESCRIPTION
  Reads open_app_in_background from the current user new Teams app settings. Exits 1 if Teams still starts hidden in the background, 0 when it starts in the foreground.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ExpectedBackgroundStart = $false
$TeamsAppName            = 'MSTeams'
$TeamsFamilyName         = 'MSTeams_8wekyb3d8bbwe'
$SettingName             = 'open_app_in_background'
$ExpectedLabel           = 'Foreground'
if ($ExpectedBackgroundStart) { $ExpectedLabel = 'Background' }

$PackageName = 'TeamsForegroundStart'
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

try {
    $ErrorActionPreference = 'Stop'

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
        Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User'
    }

    $settingsPath = Get-TeamsSettingsPath
    $state = Get-BackgroundStartState -Path $settingsPath

    if ($state -eq 'NoFile') {
        $installed = @(Get-AppxPackage -Name $TeamsAppName -ErrorAction SilentlyContinue)
        if ($installed.Count -eq 0) { Exit-Script 0 'NotApplicable | NewTeams=NotInstalled' }
        Exit-Script 0 'Skipped | SettingsFile=NotCreated'
    }

    if ($state -eq 'Unset') {
        if ($ExpectedLabel -eq 'Foreground') { Exit-Script 0 'Healthy | Setting=Unset; Effective=Foreground' }
        Exit-Script 1 'Drift | Setting=Unset; Expected=Background'
    }

    if ($state -ne $ExpectedLabel) {
        Exit-Script 1 "Drift | Setting=open_app_in_background; Current=$state; Expected=$ExpectedLabel"
    }

    Exit-Script 0 "Healthy | Setting=open_app_in_background; Current=$state"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
