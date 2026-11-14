<#
.SYNOPSIS
  Remediation script for the new Teams autostart startup task.

.DESCRIPTION
  Sets the TeamsTfwStartupTask state to enabled for the signed-in user, backs up the existing key with reg export and verifies the new value. Exits 0 when autostart is on, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ExpectedState         = 2
$TeamsPackageName      = 'MSTeams'
$TeamsFamilyName       = 'MSTeams_8wekyb3d8bbwe'
$StartupTaskId         = 'TeamsTfwStartupTask'
$StartupPolicyKey      = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$StartupPolicyValues   = @('EnableFullTrustStartupTasks', 'EnableUwpStartupTasks', 'SupportFullTrustStartupTasks', 'SupportUwpStartupTasks')
$TeamsLocalPackage     = Join-Path $env:LOCALAPPDATA "Packages\$TeamsFamilyName"
$StartupTaskRoot       = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$TeamsFamilyName\$StartupTaskId"
$StartupTaskRegPath    = "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$TeamsFamilyName\$StartupTaskId"
$BackupFolder          = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Backup'

$PackageName = 'TeamsAutoStart'
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

function Get-StartupPolicyBlock {
    $properties = Get-ItemProperty -LiteralPath $StartupPolicyKey -ErrorAction SilentlyContinue
    if ($null -eq $properties) { return '' }
    foreach ($valueName in $StartupPolicyValues) {
        $property = $properties.PSObject.Properties[$valueName]
        if ($null -eq $property) { continue }
        if ([int]$property.Value -eq 0) { return $valueName }
    }
    return ''
}

function Get-StartupStateName {
    param([int]$State)
    switch ($State) {
        0 { return 'Disabled' }
        1 { return 'DisabledByUser' }
        2 { return 'EnabledByUser' }
        3 { return 'DisabledByPolicy' }
        4 { return 'EnabledByPolicy' }
        default { return "Unknown$State" }
    }
}

function Get-StartupState {
    $value = (Get-ItemProperty -LiteralPath $StartupTaskRoot -Name 'State' -ErrorAction SilentlyContinue).State
    if ($null -eq $value) { return $null }
    return [int]$value
}

function Backup-StartupTaskKey {
    if (-not (Test-Path -LiteralPath $StartupTaskRoot)) { return 'NotPresent' }
    if (-not (Test-Path -LiteralPath $BackupFolder)) { New-Item -ItemType Directory -Path $BackupFolder -Force | Out-Null }
    $backupFile = Join-Path $BackupFolder ('TeamsTfwStartupTask_{0}.reg' -f (Get-Date -Format 'yyyyMMddHHmmss'))
    $arguments = @('export', $StartupTaskRegPath, $backupFile, '/y')
    $process = Start-Process -FilePath 'reg.exe' -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) { throw "reg export failed with exit code $($process.ExitCode)" }
    Write-IRTLog "Backup written to $backupFile"
    return 'Yes'
}

try {
    $ErrorActionPreference = 'Stop'

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
        Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User'
    }

    $teams = @(Get-AppxPackage -Name $TeamsPackageName -ErrorAction SilentlyContinue)
    if ($teams.Count -eq 0) { Exit-Script 0 'NotApplicable | NewTeams=NotInstalled' }

    $policyBlock = Get-StartupPolicyBlock
    if ($policyBlock) {
        Exit-Script 0 "NotApplicable | Reason=StartupTasksBlockedByPolicy; Value=$policyBlock; Action=ReportOnly"
    }

    $state = Get-StartupState
    if ($null -eq $state) {
        if (-not (Test-Path -LiteralPath $TeamsLocalPackage)) {
            Exit-Script 0 'Skipped | StartupTask=NotRegistered; FirstLaunch=NotDone'
        }
    }
    else {
        if ($state -eq 3) {
            Exit-Script 0 'NotApplicable | Reason=StartupTaskDisabledByPolicy; Action=ReportOnly'
        }
        if ($state -eq $ExpectedState -or $state -eq 4) {
            $stateName = Get-StartupStateName -State $state
            Exit-Script 0 "Healthy | StartupTask=$stateName; AutoStart=On"
        }
    }

    $backup = Backup-StartupTaskKey

    if (-not (Test-Path -LiteralPath $StartupTaskRoot)) {
        New-Item -Path $StartupTaskRoot -Force -ErrorAction Stop | Out-Null
    }
    New-ItemProperty -LiteralPath $StartupTaskRoot -Name 'State' -Value $ExpectedState -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -LiteralPath $StartupTaskRoot -Name 'UserEnabledStartupOnce' -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null

    $after = Get-StartupState
    if ($null -eq $after) {
        Exit-Script 1 'Failed | StartupTask=StateMissing; Expected=EnabledByUser'
    }
    if ($after -ne $ExpectedState -and $after -ne 4) {
        $afterName = Get-StartupStateName -State $after
        Exit-Script 1 "Failed | StartupTask=$afterName; Expected=EnabledByUser"
    }

    Exit-Script 0 "Fixed | StartupTask=EnabledByUser; AutoStart=On; Backup=$backup; Effective=NextSignIn"
}
catch { Exit-Script 1 ('Error: Failed | Operation=Remediate; HResult={0}' -f $_.Exception.HResult) }
